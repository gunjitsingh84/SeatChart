-- Dedicated Super Admin username/password session authentication.
-- Production account seed is applied separately; password is stored only as a SHA-256 hash.
create table if not exists public.sc_super_admin_accounts (
  id uuid primary key default gen_random_uuid(),
  username text not null unique,
  password_hash text not null,
  full_name text not null default 'Super Admin',
  active boolean not null default true,
  created_at timestamptz not null default now()
);

alter table public.sc_super_admin_accounts enable row level security;
revoke all on table public.sc_super_admin_accounts from anon, authenticated;

create table if not exists public.sc_super_admin_sessions (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.sc_super_admin_accounts(id) on delete cascade,
  token_hash text not null unique,
  expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);

create index if not exists sc_super_admin_sessions_token_hash_idx
  on public.sc_super_admin_sessions(token_hash);

alter table public.sc_super_admin_sessions enable row level security;
revoke all on table public.sc_super_admin_sessions from anon, authenticated;

alter table public.sc_super_admin_history
  add column if not exists admin_account_id uuid references public.sc_super_admin_accounts(id) on delete set null;
alter table public.sc_super_admin_history
  alter column admin_user_id drop not null;

create or replace function public.sc_super_admin_session_account(p_token text)
returns uuid language sql stable security definer set search_path=''
as $$
  select s.account_id
  from public.sc_super_admin_sessions s
  join public.sc_super_admin_accounts a on a.id=s.account_id
  where a.active
    and s.token_hash=encode(extensions.digest(coalesce(p_token,''),'sha256'),'hex')
    and s.expires_at>now()
  limit 1;
$$;
revoke all on function public.sc_super_admin_session_account(text) from public;

create or replace function public.sc_super_admin_login(p_username text,p_password text)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_account public.sc_super_admin_accounts; v_token text; v_expires timestamptz;
begin
  select * into v_account from public.sc_super_admin_accounts
  where lower(username)=lower(trim(coalesce(p_username,''))) and active limit 1;
  if v_account.id is null
     or encode(extensions.digest(coalesce(p_password,''),'sha256'),'hex')<>v_account.password_hash then
    raise exception 'Invalid Super Admin username or password.';
  end if;
  v_token=encode(extensions.gen_random_bytes(32),'hex');
  v_expires=now()+interval '8 hours';
  insert into public.sc_super_admin_sessions(account_id,token_hash,expires_at)
  values(v_account.id,encode(extensions.digest(v_token,'sha256'),'hex'),v_expires);
  return jsonb_build_object('token',v_token,'expires_at',v_expires,'id',v_account.id,'full_name',v_account.full_name,'username',v_account.username);
end;
$$;
revoke all on function public.sc_super_admin_login(text,text) from public;
grant execute on function public.sc_super_admin_login(text,text) to anon;

create or replace function public.sc_super_admin_bootstrap_token(p_token text)
returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare v_account_id uuid=public.sc_super_admin_session_account(p_token); v_account public.sc_super_admin_accounts; v_expires timestamptz;
begin
  if v_account_id is null then raise exception 'Super Admin session expired or invalid.'; end if;
  select * into v_account from public.sc_super_admin_accounts where id=v_account_id;
  select expires_at into v_expires from public.sc_super_admin_sessions where token_hash=encode(extensions.digest(p_token,'sha256'),'hex') limit 1;
  update public.sc_super_admin_sessions set last_seen_at=now() where token_hash=encode(extensions.digest(p_token,'sha256'),'hex');
  return jsonb_build_object('id',v_account.id,'full_name',v_account.full_name,'username',v_account.username,'expires_at',v_expires);
end;
$$;
revoke all on function public.sc_super_admin_bootstrap_token(text) from public;
grant execute on function public.sc_super_admin_bootstrap_token(text) to anon;

create or replace function public.sc_super_admin_logout(p_token text)
returns boolean language plpgsql security definer set search_path=''
as $$
begin
  delete from public.sc_super_admin_sessions where token_hash=encode(extensions.digest(coalesce(p_token,''),'sha256'),'hex');
  return true;
end;
$$;
revoke all on function public.sc_super_admin_logout(text) from public;
grant execute on function public.sc_super_admin_logout(text) to anon;

create or replace function public.sc_super_admin_dashboard_token(p_token text)
returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare v_result jsonb;
begin
  if public.sc_super_admin_session_account(p_token) is null then raise exception 'Super Admin session expired or invalid.'; end if;
  select jsonb_build_object(
    'totals',jsonb_build_object(
      'schools',(select count(*) from public.sc_schools),
      'active_schools',(select count(*) from public.sc_schools where status='Active'),
      'suspended_schools',(select count(*) from public.sc_schools where status='Suspended'),
      'users',(select count(*) from public.sc_user_profiles),
      'students',coalesce((select sum(student_count) from public.sc_sections),0),
      'rooms',(select count(*) from public.sc_rooms),
      'subjects',(select count(*) from public.sc_subjects),
      'exams',(select count(*) from public.sc_exams),
      'seating_plans',(select count(*) from public.sc_seating_plans)
    ),
    'new_schools',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from (
      select s.id,s.name,s.phone,s.status,s.created_at,
        (select count(*) from public.sc_user_profiles u where u.school_id=s.id) user_count,
        (select coalesce(sum(sec.student_count),0) from public.sc_sections sec where sec.school_id=s.id) student_count
      from public.sc_schools s order by s.created_at desc limit 10) x),'[]'::jsonb),
    'new_users',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from (
      select u.id,u.full_name,u.phone,u.role,u.school_id,s.name school_name,u.created_at
      from public.sc_user_profiles u left join public.sc_schools s on s.id=u.school_id
      order by u.created_at desc limit 10) x),'[]'::jsonb)
  ) into v_result;
  return v_result;
end;
$$;
revoke all on function public.sc_super_admin_dashboard_token(text) from public;
grant execute on function public.sc_super_admin_dashboard_token(text) to anon;

create or replace function public.sc_super_admin_schools_token(p_token text)
returns table(id uuid,name text,address text,phone text,status text,created_at timestamptz,user_count bigint,student_count bigint,room_count bigint,subject_count bigint,exam_count bigint,seating_plan_count bigint)
language sql stable security definer set search_path=''
as $$
  select s.id,s.name,s.address,s.phone,s.status,s.created_at,
    (select count(*) from public.sc_user_profiles u where u.school_id=s.id),
    coalesce((select sum(sec.student_count) from public.sc_sections sec where sec.school_id=s.id),0),
    (select count(*) from public.sc_rooms r where r.school_id=s.id),
    (select count(*) from public.sc_subjects sub where sub.school_id=s.id),
    (select count(*) from public.sc_exams e where e.school_id=s.id),
    (select count(*) from public.sc_seating_plans sp where sp.school_id=s.id)
  from public.sc_schools s
  where public.sc_super_admin_session_account(p_token) is not null
  order by s.created_at desc;
$$;
revoke all on function public.sc_super_admin_schools_token(text) from public;
grant execute on function public.sc_super_admin_schools_token(text) to anon;

create or replace function public.sc_super_admin_school_detail_token(p_token text,p_school_id uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare v_result jsonb;
begin
  if public.sc_super_admin_session_account(p_token) is null then raise exception 'Super Admin session expired or invalid.'; end if;
  select jsonb_build_object(
    'school',to_jsonb(s),
    'totals',jsonb_build_object(
      'users',(select count(*) from public.sc_user_profiles u where u.school_id=s.id),
      'students',coalesce((select sum(sec.student_count) from public.sc_sections sec where sec.school_id=s.id),0),
      'classes',(select count(*) from public.sc_classes c where c.school_id=s.id),
      'sections',(select count(*) from public.sc_sections sec where sec.school_id=s.id),
      'rooms',(select count(*) from public.sc_rooms r where r.school_id=s.id),
      'subjects',(select count(*) from public.sc_subjects sub where sub.school_id=s.id),
      'exams',(select count(*) from public.sc_exams e where e.school_id=s.id),
      'exam_schedules',(select count(*) from public.sc_exam_schedules es where es.school_id=s.id),
      'seating_plans',(select count(*) from public.sc_seating_plans sp where sp.school_id=s.id),
      'seating_assignments',(select count(*) from public.sc_seating_assignments sa where sa.school_id=s.id)
    ),
    'users',coalesce((select jsonb_agg(to_jsonb(u) order by u.created_at desc) from public.sc_user_profiles u where u.school_id=s.id),'[]'::jsonb),
    'sessions',coalesce((select jsonb_agg(to_jsonb(a) order by a.created_at desc) from public.sc_academic_sessions a where a.school_id=s.id),'[]'::jsonb),
    'exams',coalesce((select jsonb_agg(to_jsonb(e) order by e.created_at desc) from public.sc_exams e where e.school_id=s.id),'[]'::jsonb)
  ) into v_result
  from public.sc_schools s where s.id=p_school_id;
  if v_result is null then raise exception 'School not found.'; end if;
  return v_result;
end;
$$;
revoke all on function public.sc_super_admin_school_detail_token(text,uuid) from public;
grant execute on function public.sc_super_admin_school_detail_token(text,uuid) to anon;

create or replace function public.sc_super_admin_update_school_token(p_token text,p_school_id uuid,p_name text,p_address text,p_phone text,p_status text,p_suspension_reason text default null)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_account_id uuid=public.sc_super_admin_session_account(p_token); v_school public.sc_schools;
begin
  if v_account_id is null then raise exception 'Super Admin session expired or invalid.'; end if;
  if p_status not in ('Active','Suspended') then raise exception 'Invalid school status.'; end if;
  if coalesce(trim(p_name),'')='' then raise exception 'School name is required.'; end if;
  update public.sc_schools set name=trim(p_name),address=nullif(trim(coalesce(p_address,'')),''),phone=nullif(trim(coalesce(p_phone,'')),''),status=p_status,
    suspension_reason=case when p_status='Suspended' then nullif(trim(coalesce(p_suspension_reason,'')),'') else null end,
    suspended_at=case when p_status='Suspended' then coalesce(suspended_at,now()) else null end,updated_at=now()
  where id=p_school_id returning * into v_school;
  if not found then raise exception 'School not found.'; end if;
  insert into public.sc_super_admin_history(admin_user_id,admin_account_id,school_id,action,description)
  values(null,v_account_id,p_school_id,'Updated School',case when p_status='Suspended' then 'School updated and suspended.' else 'School updated and active.' end);
  return to_jsonb(v_school);
end;
$$;
revoke all on function public.sc_super_admin_update_school_token(text,uuid,text,text,text,text,text) from public;
grant execute on function public.sc_super_admin_update_school_token(text,uuid,text,text,text,text,text) to anon;

create or replace function public.sc_super_admin_users_token(p_token text)
returns jsonb language sql stable security definer set search_path=''
as $$
  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb)
  from (
    select u.id,u.full_name,u.phone,u.role,u.school_id,s.name school_name,s.status school_status,u.created_at
    from public.sc_user_profiles u left join public.sc_schools s on s.id=u.school_id
    where public.sc_super_admin_session_account(p_token) is not null
  ) x;
$$;
revoke all on function public.sc_super_admin_users_token(text) from public;
grant execute on function public.sc_super_admin_users_token(text) to anon;

delete from public.sc_super_admin_sessions where expires_at<=now();

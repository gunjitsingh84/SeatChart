create table if not exists public.sc_super_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.sc_super_admins enable row level security;
revoke all on table public.sc_super_admins from anon, authenticated;

alter table public.sc_schools
  add column if not exists status text not null default 'Active',
  add column if not exists suspension_reason text,
  add column if not exists suspended_at timestamptz;

alter table public.sc_schools drop constraint if exists sc_schools_status_check;
alter table public.sc_schools add constraint sc_schools_status_check check (status = any (array['Active'::text,'Suspended'::text]));

create table if not exists public.sc_super_admin_history (
  id uuid primary key default gen_random_uuid(),
  admin_user_id uuid not null references auth.users(id),
  school_id uuid references public.sc_schools(id) on delete set null,
  action text not null,
  description text,
  created_at timestamptz not null default now()
);

alter table public.sc_super_admin_history enable row level security;
revoke all on table public.sc_super_admin_history from anon, authenticated;

create or replace function public.sc_is_super_admin()
returns boolean language sql stable security definer set search_path = ''
as $$ select exists (select 1 from public.sc_super_admins where user_id = (select auth.uid())); $$;
revoke all on function public.sc_is_super_admin() from public;
grant execute on function public.sc_is_super_admin() to authenticated;

create or replace function public.sc_super_admin_bootstrap()
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare v_uid uuid := (select auth.uid()); v_profile jsonb;
begin
  if v_uid is null or not exists (select 1 from public.sc_super_admins where user_id=v_uid) then raise exception 'Super Admin access is not authorized.'; end if;
  select jsonb_build_object('id',p.id,'full_name',p.full_name,'phone',p.phone) into v_profile from public.sc_user_profiles p where p.id=v_uid;
  return coalesce(v_profile,jsonb_build_object('id',v_uid));
end; $$;
revoke all on function public.sc_super_admin_bootstrap() from public;
grant execute on function public.sc_super_admin_bootstrap() to authenticated;

create or replace function public.sc_super_admin_dashboard()
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare v_result jsonb;
begin
  if not public.sc_is_super_admin() then raise exception 'Super Admin access is not authorized.'; end if;
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
        (select count(*) from public.sc_user_profiles u where u.school_id=s.id) as user_count,
        (select coalesce(sum(sec.student_count),0) from public.sc_sections sec where sec.school_id=s.id) as student_count
      from public.sc_schools s order by s.created_at desc limit 10) x),'[]'::jsonb),
    'new_users',coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at desc) from (
      select u.id,u.full_name,u.phone,u.role,u.school_id,s.name as school_name,u.created_at
      from public.sc_user_profiles u left join public.sc_schools s on s.id=u.school_id
      order by u.created_at desc limit 10) x),'[]'::jsonb)
  ) into v_result;
  return v_result;
end; $$;
revoke all on function public.sc_super_admin_dashboard() from public;
grant execute on function public.sc_super_admin_dashboard() to authenticated;

create or replace function public.sc_super_admin_schools()
returns table(id uuid,name text,address text,phone text,status text,created_at timestamptz,user_count bigint,student_count bigint,room_count bigint,subject_count bigint,exam_count bigint,seating_plan_count bigint)
language sql stable security definer set search_path = ''
as $$
  select s.id,s.name,s.address,s.phone,s.status,s.created_at,
    (select count(*) from public.sc_user_profiles u where u.school_id=s.id),
    coalesce((select sum(sec.student_count) from public.sc_sections sec where sec.school_id=s.id),0),
    (select count(*) from public.sc_rooms r where r.school_id=s.id),
    (select count(*) from public.sc_subjects sub where sub.school_id=s.id),
    (select count(*) from public.sc_exams e where e.school_id=s.id),
    (select count(*) from public.sc_seating_plans sp where sp.school_id=s.id)
  from public.sc_schools s where public.sc_is_super_admin() order by s.created_at desc;
$$;
revoke all on function public.sc_super_admin_schools() from public;
grant execute on function public.sc_super_admin_schools() to authenticated;

create or replace function public.sc_super_admin_school_detail(p_school_id uuid)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare v_result jsonb;
begin
  if not public.sc_is_super_admin() then raise exception 'Super Admin access is not authorized.'; end if;
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
  ) into v_result from public.sc_schools s where s.id=p_school_id;
  if v_result is null then raise exception 'School not found.'; end if;
  return v_result;
end; $$;
revoke all on function public.sc_super_admin_school_detail(uuid) from public;
grant execute on function public.sc_super_admin_school_detail(uuid) to authenticated;

create or replace function public.sc_super_admin_update_school(p_school_id uuid,p_name text,p_address text,p_phone text,p_status text,p_suspension_reason text default null)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_uid uuid := (select auth.uid()); v_school public.sc_schools;
begin
  if v_uid is null or not public.sc_is_super_admin() then raise exception 'Super Admin access is not authorized.'; end if;
  if p_status not in ('Active','Suspended') then raise exception 'Invalid school status.'; end if;
  if coalesce(trim(p_name),'')='' then raise exception 'School name is required.'; end if;
  update public.sc_schools set name=trim(p_name),address=nullif(trim(coalesce(p_address,'')),''),phone=nullif(trim(coalesce(p_phone,'')),''),status=p_status,
    suspension_reason=case when p_status='Suspended' then nullif(trim(coalesce(p_suspension_reason,'')),'') else null end,
    suspended_at=case when p_status='Suspended' then coalesce(suspended_at,now()) else null end,updated_at=now()
  where id=p_school_id returning * into v_school;
  if not found then raise exception 'School not found.'; end if;
  insert into public.sc_super_admin_history(admin_user_id,school_id,action,description)
  values(v_uid,p_school_id,'Updated School',case when p_status='Suspended' then 'School updated and suspended.' else 'School updated and active.' end);
  return to_jsonb(v_school);
end; $$;
revoke all on function public.sc_super_admin_update_school(uuid,text,text,text,text,text) from public;
grant execute on function public.sc_super_admin_update_school(uuid,text,text,text,text,text) to authenticated;

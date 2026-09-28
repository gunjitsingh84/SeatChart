create or replace function public.sc_super_admin_users()
returns table(
  id uuid,
  full_name text,
  phone text,
  role text,
  school_id uuid,
  school_name text,
  school_status text,
  created_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select u.id,u.full_name,u.phone,u.role,u.school_id,s.name,s.status,u.created_at
  from public.sc_user_profiles u
  left join public.sc_schools s on s.id=u.school_id
  where public.sc_is_super_admin()
  order by u.created_at desc;
$$;

revoke all on function public.sc_super_admin_users() from public;
grant execute on function public.sc_super_admin_users() to authenticated;
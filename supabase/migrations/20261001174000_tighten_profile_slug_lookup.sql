create or replace function private.lookup_profile_slug(target_slug text)
returns table(profile_id uuid, profile_slug text, display_name text, avatar_path text)
language sql
stable
security definer
set search_path = ''
as $$
  select p.id, p.profile_slug, p.display_name, p.avatar_path
  from public.profiles p
  where p.profile_slug = lower(trim(both '@' from trim(target_slug)))
  limit 1;
$$;

revoke all on function private.lookup_profile_slug(text) from public, anon, authenticated;
grant usage on schema private to anon;
grant execute on function private.lookup_profile_slug(text) to anon, authenticated;

create or replace function public.lookup_profile_slug(target_slug text)
returns table(profile_id uuid, profile_slug text, display_name text, avatar_path text)
language sql
stable
set search_path = ''
as $$
  select * from private.lookup_profile_slug(target_slug);
$$;

revoke all on function public.lookup_profile_slug(text) from public, anon, authenticated;
grant execute on function public.lookup_profile_slug(text) to anon, authenticated;

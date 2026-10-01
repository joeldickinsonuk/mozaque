create or replace function private.lookup_profile_slug(target_slug text)
returns table(profile_id uuid, profile_slug text, display_name text, avatar_path text)
language sql
stable
security definer
set search_path = ''
as $$
  select
    case when (select auth.uid()) is null then null::uuid else p.id end,
    p.profile_slug,
    p.display_name,
    case when (select auth.uid()) is null then null::text else p.avatar_path end
  from public.profiles p
  where p.profile_slug = lower(trim(both '@' from trim(target_slug)))
  limit 1;
$$;

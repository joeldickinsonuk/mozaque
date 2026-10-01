alter table public.galleries
  add column is_public boolean not null default false;

-- Preserve any gallery owners had already chosen to show on their profiles.
update public.galleries g
set is_public = true
from public.profiles p
where p.public_gallery_id = g.id
  and g.owner_id = p.id;

create index galleries_public_owner_created_idx
  on public.galleries(owner_id, created_at desc)
  where is_public;

create or replace function public.set_gallery_visibility(
  target_gallery uuid,
  make_public boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Sign in to change Mozaque visibility.';
  end if;

  update public.galleries
  set is_public = make_public
  where id = target_gallery
    and owner_id = auth.uid();

  if not found then
    raise exception 'Only the owner can change this Mozaque’s visibility.';
  end if;
end;
$$;

revoke all on function public.set_gallery_visibility(uuid, boolean)
  from public, anon;
grant execute on function public.set_gallery_visibility(uuid, boolean)
  to authenticated;

create or replace function private.public_profile_galleries(target_slug text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    jsonb_agg(public_gallery.gallery_json order by public_gallery.created_at desc),
    '[]'::jsonb
  )
  from (
    select
      g.created_at,
      jsonb_build_object(
        'gallery_id', g.id,
        'title', g.title,
        'description', g.description,
        'event_type', g.event_type,
        'event_date', g.event_date,
        'photo_count', (
          select count(*)
          from public.photos ph
          where ph.gallery_id = g.id
        ),
        'photos', coalesce((
          select jsonb_agg(
            jsonb_build_object(
              'storage_path', public_photo.storage_path,
              'caption', public_photo.caption,
              'created_at', public_photo.created_at
            ) order by public_photo.created_at desc
          )
          from (
            select ph.storage_path, ph.caption, ph.created_at
            from public.photos ph
            where ph.gallery_id = g.id
            order by ph.created_at desc
            limit 40
          ) public_photo
        ), '[]'::jsonb)
      ) as gallery_json
    from public.profiles p
    join public.galleries g
      on g.owner_id = p.id
     and g.is_public
    where p.profile_slug = lower(trim(both '@' from trim(target_slug)))
  ) public_gallery;
$$;

revoke all on function private.public_profile_galleries(text)
  from public, anon, authenticated;
grant usage on schema private to anon;
grant execute on function private.public_profile_galleries(text)
  to anon, authenticated;

create or replace function public.public_profile_galleries(target_slug text)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select private.public_profile_galleries(target_slug);
$$;

revoke all on function public.public_profile_galleries(text)
  from public, anon, authenticated;
grant execute on function public.public_profile_galleries(text)
  to anon, authenticated;

-- Keep the old single-gallery RPC compatible, but never expose a gallery
-- unless it is currently public.
create or replace function private.public_profile_gallery(target_slug text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select private.public_profile_galleries(target_slug) -> 0;
$$;

create or replace function private.can_sign_public_profile_photo(target_path text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.photos ph
    join public.galleries g on g.id = ph.gallery_id
    where ph.storage_path = target_path
      and g.is_public
  );
$$;

revoke all on function private.can_sign_public_profile_photo(text)
  from public, anon, authenticated;
grant usage on schema private to anon;
grant execute on function private.can_sign_public_profile_photo(text)
  to anon, authenticated;

alter table public.galleries
  add column cover_photo_id uuid
  references public.photos(id) on delete set null;

create or replace function private.set_gallery_cover_photo(
  target_gallery uuid,
  target_photo uuid
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
begin
  if caller_id is null then
    raise exception using
      errcode = '42501',
      message = 'A signed-in account is required to change the cover photo.';
  end if;

  if not exists (
    select 1
    from public.galleries g
    where g.id = target_gallery
      and g.owner_id = caller_id
      and g.frozen_at is null
  ) then
    raise exception using
      errcode = '42501',
      message = 'Only the owner of an open Mozaque can change its cover photo.';
  end if;

  if target_photo is not null and not exists (
    select 1
    from public.photos p
    where p.id = target_photo
      and p.gallery_id = target_gallery
  ) then
    raise exception using
      errcode = '22023',
      message = 'Choose a photo from this Mozaque.';
  end if;

  update public.galleries
  set cover_photo_id = target_photo
  where id = target_gallery;
end;
$$;

create or replace function public.set_gallery_cover_photo(
  target_gallery uuid,
  target_photo uuid
) returns void
language sql
security invoker
set search_path = ''
as $$
  select private.set_gallery_cover_photo(target_gallery, target_photo);
$$;

revoke all on function private.set_gallery_cover_photo(uuid, uuid)
  from public, anon, authenticated;
grant execute on function private.set_gallery_cover_photo(uuid, uuid)
  to authenticated;
revoke all on function public.set_gallery_cover_photo(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.set_gallery_cover_photo(uuid, uuid)
  to authenticated;

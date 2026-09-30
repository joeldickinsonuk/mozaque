-- Give existing Mozaques a useful starting cover from their first uploaded photo.
update public.galleries g
set cover_photo_id = (
  select p.id
  from public.photos p
  where p.gallery_id = g.id
  order by p.created_at, p.id
  limit 1
)
where g.cover_photo_id is null
  and exists (select 1 from public.photos p where p.gallery_id = g.id);

-- The first uploaded photo becomes the initial cover; owners can change it later.
create or replace function private.set_initial_gallery_cover_photo()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.galleries
  set cover_photo_id = new.id
  where id = new.gallery_id
    and cover_photo_id is null;
  return new;
end;
$$;

revoke all on function private.set_initial_gallery_cover_photo()
  from public, anon, authenticated;

create trigger set_initial_gallery_cover_photo
after insert on public.photos
for each row execute function private.set_initial_gallery_cover_photo();

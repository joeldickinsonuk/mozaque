create or replace function private.clear_gallery_cover_for_deletion()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.galleries
  set cover_photo_id = null
  where id = new.gallery_id and owner_id = new.owner_id;
  return new;
end;
$$;

revoke all on function private.clear_gallery_cover_for_deletion()
  from public, anon, authenticated;

create trigger clear_gallery_cover_on_delete_request
  after insert on public.gallery_deletion_requests
  for each row execute function private.clear_gallery_cover_for_deletion();

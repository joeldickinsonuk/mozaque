alter table public.profiles
  add column public_gallery_id uuid
  references public.galleries(id) on delete set null;

create index profiles_public_gallery_id_idx
  on public.profiles(public_gallery_id)
  where public_gallery_id is not null;

create or replace function private.validate_public_profile_gallery()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.public_gallery_id is not null and not exists (
    select 1
    from public.galleries g
    where g.id = new.public_gallery_id
      and g.owner_id = new.id
  ) then
    raise exception 'You can only feature a Mozaque you own.';
  end if;
  return new;
end;
$$;

revoke all on function private.validate_public_profile_gallery()
  from public, anon, authenticated;

create trigger validate_public_profile_gallery_owner
before insert or update of public_gallery_id on public.profiles
for each row execute function private.validate_public_profile_gallery();

create or replace function private.public_profile_gallery(target_slug text)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
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
  )
  from public.profiles p
  join public.galleries g
    on g.id = p.public_gallery_id
   and g.owner_id = p.id
  where p.profile_slug = lower(trim(both '@' from trim(target_slug)))
  limit 1;
$$;

revoke all on function private.public_profile_gallery(text)
  from public, anon, authenticated;
grant usage on schema private to anon;
grant execute on function private.public_profile_gallery(text)
  to anon, authenticated;

create or replace function public.public_profile_gallery(target_slug text)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select private.public_profile_gallery(target_slug);
$$;

revoke all on function public.public_profile_gallery(text)
  from public, anon, authenticated;
grant execute on function public.public_profile_gallery(text)
  to anon, authenticated;

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
    join public.profiles p on p.public_gallery_id = ph.gallery_id
    join public.galleries g on g.id = ph.gallery_id and g.owner_id = p.id
    where ph.storage_path = target_path
  );
$$;

revoke all on function private.can_sign_public_profile_photo(text)
  from public, anon, authenticated;
grant usage on schema private to anon;
grant execute on function private.can_sign_public_profile_photo(text)
  to anon, authenticated;

drop policy if exists mozaque_public_profile_photo_sign on storage.objects;
create policy mozaque_public_profile_photo_sign
  on storage.objects for select to anon, authenticated
  using (
    bucket_id = 'mozaque-photos'
    and storage.allow_only_operation('storage.object.sign')
    and private.can_sign_public_profile_photo(name)
  );

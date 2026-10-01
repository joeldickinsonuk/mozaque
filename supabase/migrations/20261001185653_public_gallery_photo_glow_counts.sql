create or replace function private.public_profile_gallery_detail(
  target_slug text,
  target_gallery uuid
)
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
    'cover_storage_path', coalesce(
      (
        select ph.storage_path
        from public.photos ph
        where ph.id = g.cover_photo_id
          and ph.gallery_id = g.id
      ),
      (
        select ph.storage_path
        from public.photos ph
        where ph.gallery_id = g.id
        order by ph.created_at desc
        limit 1
      )
    ),
    'photos', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'storage_path', public_photo.storage_path,
          'caption', public_photo.caption,
          'created_at', public_photo.created_at,
          'glow_count', (
            select count(*)
            from public.glows glow
            where glow.photo_id = public_photo.id
          )
        ) order by public_photo.created_at desc
      )
      from (
        select ph.id, ph.storage_path, ph.caption, ph.created_at
        from public.photos ph
        where ph.gallery_id = g.id
        order by ph.created_at desc
        limit 40
      ) public_photo
    ), '[]'::jsonb)
  )
  from public.profiles p
  join public.galleries g
    on g.owner_id = p.id
   and g.is_public
  where p.profile_slug = lower(trim(both '@' from trim(target_slug)))
    and g.id = target_gallery
  limit 1;
$$;

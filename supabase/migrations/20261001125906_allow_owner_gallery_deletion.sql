create table public.gallery_deletion_requests (
  gallery_id uuid primary key references public.galleries(id) on delete cascade,
  owner_id uuid not null references public.profiles(id) on delete cascade,
  requested_at timestamptz not null default now()
);

alter table public.gallery_deletion_requests enable row level security;

create policy gallery_deletion_requests_read_own
  on public.gallery_deletion_requests for select to authenticated
  using (owner_id = (select auth.uid()));
create policy gallery_deletion_requests_create_own
  on public.gallery_deletion_requests for insert to authenticated
  with check (
    owner_id = (select auth.uid())
    and exists (
      select 1 from public.galleries g
      where g.id = gallery_id and g.owner_id = (select auth.uid())
    )
  );

grant select, insert on public.gallery_deletion_requests to authenticated;

-- A deletion request closes the gallery to new uploads while its images are
-- removed from private Storage. It also grants its owner temporary access to
-- delete stored files even when the gallery had been preserved.
create or replace function private.can_upload_gallery(target_gallery uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists(
    select 1
    from public.galleries g
    where g.id = target_gallery
      and g.frozen_at is null
      and not exists (
        select 1 from public.gallery_deletion_requests d
        where d.gallery_id = g.id
      )
      and (
        g.owner_id = auth.uid()
        or (
          g.upload_policy = 'everyone'
          and (
            exists (
              select 1 from public.gallery_members m
              where m.gallery_id = g.id and m.user_id = auth.uid()
            )
            or (g.audience = 'connections' and private.are_connected(g.owner_id))
          )
        )
        or (
          g.upload_policy = 'selected'
          and exists (
            select 1 from public.gallery_members m
            where m.gallery_id = g.id
              and m.user_id = auth.uid()
              and m.role = 'contributor'
          )
        )
      )
  );
$$;

drop policy if exists mozaque_photos_delete on storage.objects;
create policy mozaque_photos_delete
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'mozaque-photos'
    and (
      private.can_delete_gallery_photo(
        (storage.foldername(name))[1]::uuid,
        (storage.foldername(name))[2]::uuid
      )
      or exists (
        select 1 from public.gallery_deletion_requests d
        where d.gallery_id = (storage.foldername(name))[1]::uuid
          and d.owner_id = (select auth.uid())
      )
    )
  );

create policy galleries_delete_own
  on public.galleries for delete to authenticated
  using (owner_id = (select auth.uid()));
grant delete on public.galleries to authenticated;

revoke all on function private.can_upload_gallery(uuid)
  from public, anon, authenticated;
grant execute on function private.can_upload_gallery(uuid) to authenticated;

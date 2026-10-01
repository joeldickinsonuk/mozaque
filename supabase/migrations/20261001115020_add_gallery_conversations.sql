create table public.photo_notes (
  id uuid primary key default gen_random_uuid(),
  photo_id uuid not null references public.photos(id) on delete cascade,
  author_id uuid not null references public.profiles(id) on delete cascade,
  body text not null check (char_length(trim(body)) between 1 and 1000),
  created_at timestamptz not null default now()
);

create table public.guestbook_entries (
  id uuid primary key default gen_random_uuid(),
  gallery_id uuid not null references public.galleries(id) on delete cascade,
  author_id uuid not null references public.profiles(id) on delete cascade,
  body text not null check (char_length(trim(body)) between 1 and 1000),
  created_at timestamptz not null default now()
);

create index photo_notes_photo_date on public.photo_notes(photo_id, created_at desc);
create index guestbook_entries_gallery_date on public.guestbook_entries(gallery_id, created_at desc);

alter table public.photo_notes enable row level security;
alter table public.guestbook_entries enable row level security;

create policy photo_notes_read on public.photo_notes for select to authenticated using (
  exists (
    select 1 from public.photos p
    where p.id = photo_id and private.can_view_gallery(p.gallery_id)
  )
);
create policy photo_notes_create on public.photo_notes for insert to authenticated with check (
  author_id = (select auth.uid()) and exists (
    select 1 from public.photos p join public.galleries g on g.id = p.gallery_id
    where p.id = photo_id
      and private.can_view_gallery(p.gallery_id)
      and g.frozen_at is null
  )
);
create policy photo_notes_remove on public.photo_notes for delete to authenticated using (
  author_id = (select auth.uid()) or exists (
    select 1 from public.photos p join public.galleries g on g.id = p.gallery_id
    where p.id = photo_id and g.owner_id = (select auth.uid())
  )
);

create policy guestbook_entries_read on public.guestbook_entries for select to authenticated
  using (private.can_view_gallery(gallery_id));
create policy guestbook_entries_create on public.guestbook_entries for insert to authenticated
  with check (
    author_id = (select auth.uid())
    and private.can_view_gallery(gallery_id)
    and exists (
      select 1 from public.galleries g
      where g.id = gallery_id and g.frozen_at is null
    )
  );
create policy guestbook_entries_remove on public.guestbook_entries for delete to authenticated
  using (
    author_id = (select auth.uid()) or exists (
      select 1 from public.galleries g
      where g.id = gallery_id and g.owner_id = (select auth.uid())
    )
  );

grant select, insert, delete on public.photo_notes, public.guestbook_entries to authenticated;

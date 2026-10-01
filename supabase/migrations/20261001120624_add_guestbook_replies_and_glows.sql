alter table public.guestbook_entries
  add column parent_id uuid;

alter table public.guestbook_entries
  add constraint guestbook_entries_id_gallery_unique unique (id, gallery_id),
  add constraint guestbook_entries_parent_gallery_fkey
    foreign key (parent_id, gallery_id)
    references public.guestbook_entries(id, gallery_id)
    on delete cascade;

create index guestbook_entries_parent_date
  on public.guestbook_entries(parent_id, created_at)
  where parent_id is not null;

create or replace function private.prevent_nested_guestbook_replies()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  parent_parent_id uuid;
begin
  if new.parent_id is null then
    return new;
  end if;

  select e.parent_id into parent_parent_id
  from public.guestbook_entries e
  where e.id = new.parent_id and e.gallery_id = new.gallery_id;

  if not found then
    raise exception 'That guestbook comment is no longer available.';
  end if;
  if parent_parent_id is not null then
    raise exception 'Replies can only be added to a gallery comment.';
  end if;
  return new;
end;
$$;

create trigger prevent_nested_guestbook_replies
before insert on public.guestbook_entries
for each row execute function private.prevent_nested_guestbook_replies();

-- In connection-shared Mozaques, readers may not be directly connected to one
-- another. Allow them to see the names of other people who can view the same
-- connection-shared gallery so guestbook authorship remains meaningful.
create or replace function private.can_view_profile(target_user uuid)
returns boolean
language sql stable security definer set search_path = '' as $$
  select target_user = auth.uid()
    or private.are_connected(target_user)
    or exists (
      select 1
      from public.gallery_members a
      join public.gallery_members b on a.gallery_id = b.gallery_id
      where a.user_id = auth.uid() and b.user_id = target_user
    )
    or exists (
      select 1
      from public.galleries g
      join public.connections c on
        (c.user_a = target_user and c.user_b = g.owner_id)
        or (c.user_b = target_user and c.user_a = g.owner_id)
      where g.audience = 'connections'
        and private.are_connected(g.owner_id)
    );
$$;

create table public.guestbook_glows (
  entry_id uuid not null references public.guestbook_entries(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (entry_id, user_id)
);

create index guestbook_glows_user on public.guestbook_glows(user_id, entry_id);
alter table public.guestbook_glows enable row level security;

create policy guestbook_glows_read on public.guestbook_glows for select to authenticated
  using (
    exists (
      select 1 from public.guestbook_entries e
      where e.id = entry_id and private.can_view_gallery(e.gallery_id)
    )
  );
create policy guestbook_glows_create on public.guestbook_glows for insert to authenticated
  with check (
    user_id = (select auth.uid()) and exists (
      select 1 from public.guestbook_entries e
      join public.galleries g on g.id = e.gallery_id
      where e.id = entry_id
        and private.can_view_gallery(e.gallery_id)
        and g.frozen_at is null
    )
  );
create policy guestbook_glows_remove on public.guestbook_glows for delete to authenticated
  using (user_id = (select auth.uid()));

grant select, insert, delete on public.guestbook_glows to authenticated;
revoke all on function private.prevent_nested_guestbook_replies() from public, anon, authenticated;

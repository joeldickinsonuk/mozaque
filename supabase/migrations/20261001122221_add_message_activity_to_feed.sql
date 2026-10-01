alter table public.notifications
  add column photo_note_id uuid references public.photo_notes(id) on delete cascade,
  add column guestbook_entry_id uuid references public.guestbook_entries(id) on delete cascade;

alter table public.notifications
  drop constraint if exists notifications_kind_check,
  add constraint notifications_kind_check check (
    kind in (
      'glow',
      'member_added',
      'member_joined',
      'member_role_changed',
      'gallery_preserved',
      'gallery_settings_changed',
      'connection_added',
      'photo_note',
      'guestbook_message',
      'guestbook_reply'
    )
  );

alter table public.notifications
  drop constraint if exists notifications_target_check,
  add constraint notifications_target_check check (
    kind = 'connection_added'
    or gallery_id is not null
    or photo_id is not null
  );

-- The original key deduplicated notifications by photo, which would hide later
-- notes from the same person on the same photo. Keep glow deduplication while
-- identifying each message notification by its own message row.
alter table public.notifications
  drop constraint if exists notifications_recipient_id_actor_id_kind_photo_id_key;

create unique index notifications_glow_unique
  on public.notifications(recipient_id, actor_id, kind, photo_id)
  where kind = 'glow';
create unique index notifications_photo_note_unique
  on public.notifications(recipient_id, photo_note_id)
  where photo_note_id is not null;
create unique index notifications_guestbook_entry_unique
  on public.notifications(recipient_id, guestbook_entry_id)
  where guestbook_entry_id is not null;

-- A notification can contain a private message preview, so remove it from the
-- recipient's feed if that recipient later loses access to its Mozaque.
drop policy if exists notifications_read_own on public.notifications;
create policy notifications_read_own
  on public.notifications for select to authenticated
  using (
    (select auth.uid()) = recipient_id
    and (gallery_id is null or private.can_view_gallery(gallery_id))
  );

create or replace function private.notify_photo_note_activity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_gallery uuid;
  actor_name text;
begin
  select p.gallery_id into target_gallery
  from public.photos p
  where p.id = new.photo_id;

  if target_gallery is null then
    return new;
  end if;

  select coalesce(pr.display_name, 'Someone') into actor_name
  from public.profiles pr
  where pr.id = new.author_id;

  insert into public.notifications (
    recipient_id, actor_id, actor_name, kind, photo_id, gallery_id,
    photo_note_id, detail
  )
  select recipients.user_id, new.author_id, coalesce(actor_name, 'Someone'),
         'photo_note', new.photo_id, target_gallery, new.id,
         left(regexp_replace(new.body, '\s+', ' ', 'g'), 180)
  from (
    select g.owner_id as user_id
    from public.galleries g where g.id = target_gallery
    union
    select gm.user_id
    from public.gallery_members gm where gm.gallery_id = target_gallery
    union
    select case when c.user_a = g.owner_id then c.user_b else c.user_a end
    from public.galleries g
    join public.connections c
      on c.user_a = g.owner_id or c.user_b = g.owner_id
    where g.id = target_gallery and g.audience = 'connections'
  ) recipients
  where recipients.user_id <> new.author_id
  on conflict do nothing;

  return new;
end;
$$;

create or replace function private.notify_guestbook_activity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_name text;
  activity_kind text;
begin
  select coalesce(pr.display_name, 'Someone') into actor_name
  from public.profiles pr
  where pr.id = new.author_id;

  activity_kind := case
    when new.parent_id is null then 'guestbook_message'
    else 'guestbook_reply'
  end;

  insert into public.notifications (
    recipient_id, actor_id, actor_name, kind, gallery_id,
    guestbook_entry_id, detail
  )
  select recipients.user_id, new.author_id, coalesce(actor_name, 'Someone'),
         activity_kind, new.gallery_id, new.id,
         left(regexp_replace(new.body, '\s+', ' ', 'g'), 180)
  from (
    select g.owner_id as user_id
    from public.galleries g where g.id = new.gallery_id
    union
    select gm.user_id
    from public.gallery_members gm where gm.gallery_id = new.gallery_id
    union
    select case when c.user_a = g.owner_id then c.user_b else c.user_a end
    from public.galleries g
    join public.connections c
      on c.user_a = g.owner_id or c.user_b = g.owner_id
    where g.id = new.gallery_id and g.audience = 'connections'
  ) recipients
  where recipients.user_id <> new.author_id
  on conflict do nothing;

  return new;
end;
$$;

revoke all on function private.notify_photo_note_activity()
  from public, anon, authenticated;
revoke all on function private.notify_guestbook_activity()
  from public, anon, authenticated;

create trigger notify_on_photo_note_insert
  after insert on public.photo_notes
  for each row execute function private.notify_photo_note_activity();
create trigger notify_on_guestbook_entry_insert
  after insert on public.guestbook_entries
  for each row execute function private.notify_guestbook_activity();

-- Glow notifications still deduplicate per person/photo after replacing the
-- table-level unique constraint with message-specific keys.
create or replace function private.notify_photo_owner_of_glow()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.notifications (
    recipient_id, actor_id, actor_name, kind, photo_id, gallery_id, detail
  )
  select p.uploader_id, new.user_id, pr.display_name, 'glow', p.id,
         p.gallery_id, 'Glowed your photo'
  from public.photos p
  join public.profiles pr on pr.id = new.user_id
  where p.id = new.photo_id
    and p.uploader_id <> new.user_id
  on conflict do nothing;
  return new;
end;
$$;

alter table public.notifications
  add column gallery_id uuid references public.galleries(id) on delete cascade,
  add column detail text not null default '';

alter table public.notifications
  alter column photo_id drop not null,
  drop constraint if exists notifications_kind_check;

alter table public.notifications
  add constraint notifications_kind_check check (
    kind in (
      'glow',
      'member_added',
      'member_joined',
      'member_role_changed',
      'gallery_preserved',
      'gallery_settings_changed',
      'connection_added'
    )
  ),
  drop constraint if exists notifications_target_check;

alter table public.notifications
  add constraint notifications_target_check check (
    kind = 'connection_added' or gallery_id is not null or photo_id is not null
  );

update public.notifications n
set gallery_id = p.gallery_id
from public.photos p
where n.photo_id = p.id and n.gallery_id is null;

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
  on conflict (recipient_id, actor_id, kind, photo_id) do nothing;
  return new;
end;
$$;

create or replace function private.notify_gallery_member_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  gallery_owner uuid;
  gallery_title text;
  owner_name text;
  member_name text;
begin
  select g.owner_id, g.title, owner_profile.display_name
    into gallery_owner, gallery_title, owner_name
  from public.galleries g
  join public.profiles owner_profile on owner_profile.id = g.owner_id
  where g.id = new.gallery_id;

  if gallery_owner is null then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if new.user_id = gallery_owner then
      return new;
    end if;

    if (select auth.uid()) = new.user_id then
      select display_name into member_name
      from public.profiles where id = new.user_id;
      insert into public.notifications (
        recipient_id, actor_id, actor_name, kind, gallery_id, detail
      ) values (
        gallery_owner, new.user_id, coalesce(member_name, 'Someone'),
        'member_joined', new.gallery_id,
        'Joined ' || gallery_title
      );
    else
      insert into public.notifications (
        recipient_id, actor_id, actor_name, kind, gallery_id, detail
      ) values (
        new.user_id, gallery_owner, owner_name,
        'member_added', new.gallery_id,
        'You were added to ' || gallery_title
      );
    end if;
  elsif tg_op = 'UPDATE' then
    if new.role is distinct from old.role then
      insert into public.notifications (
        recipient_id, actor_id, actor_name, kind, gallery_id, detail
      ) values (
        new.user_id, gallery_owner, owner_name,
        'member_role_changed', new.gallery_id,
        case new.role
          when 'contributor' then 'You can now add photos'
          else 'You can view photos but cannot add them'
        end
      );
    end if;
  end if;

  return new;
end;
$$;

create trigger notify_on_gallery_member_insert
  after insert on public.gallery_members
  for each row execute function private.notify_gallery_member_change();

create trigger notify_on_gallery_member_role_change
  after update of role on public.gallery_members
  for each row execute function private.notify_gallery_member_change();

create or replace function private.notify_gallery_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  changed_detail text := '';
  owner_name text;
begin
  if new.audience is distinct from old.audience then
    changed_detail := changed_detail || case new.audience
      when 'connections' then 'Visibility now includes the owner’s connections. '
      else 'Visibility is now invite-only. '
    end;
  end if;

  if new.upload_policy is distinct from old.upload_policy then
    changed_detail := changed_detail || case new.upload_policy
      when 'owner' then 'Only the owner can add photos. '
      when 'selected' then 'Selected contributors can add photos. '
      else 'Everyone invited can add photos. '
    end;
  end if;

  if changed_detail <> '' then
    select display_name into owner_name
    from public.profiles where id = new.owner_id;

    insert into public.notifications (
      recipient_id, actor_id, actor_name, kind, gallery_id, detail
    )
    select recipients.user_id, new.owner_id, coalesce(owner_name, 'The owner'),
           'gallery_settings_changed', new.id, trim(changed_detail)
    from (
      select gm.user_id from public.gallery_members gm
      where gm.gallery_id = new.id
      union
      select case when c.user_a = new.owner_id then c.user_b else c.user_a end
      from public.connections c
      where (old.audience = 'connections' or new.audience = 'connections')
        and (c.user_a = new.owner_id or c.user_b = new.owner_id)
    ) recipients
    where recipients.user_id <> new.owner_id;
  end if;

  if old.frozen_at is null and new.frozen_at is not null then
    select display_name into owner_name
    from public.profiles where id = new.owner_id;

    insert into public.notifications (
      recipient_id, actor_id, actor_name, kind, gallery_id, detail
    )
    select recipients.user_id, new.owner_id, coalesce(owner_name, 'The owner'),
           'gallery_preserved', new.id, 'Preserved ' || new.title
    from (
      select gm.user_id from public.gallery_members gm
      where gm.gallery_id = new.id
      union
      select case when c.user_a = new.owner_id then c.user_b else c.user_a end
      from public.connections c
      where new.audience = 'connections'
        and (c.user_a = new.owner_id or c.user_b = new.owner_id)
    ) recipients
    where recipients.user_id <> new.owner_id;
  end if;

  return new;
end;
$$;

create trigger notify_on_gallery_settings_or_preserved
  after update of audience, upload_policy, frozen_at on public.galleries
  for each row execute function private.notify_gallery_update();

create or replace function private.notify_connection_added()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  new_connection uuid := (select auth.uid());
  inviter uuid;
  actor_name text;
begin
  if new_connection = new.user_a then
    inviter := new.user_b;
  elsif new_connection = new.user_b then
    inviter := new.user_a;
  else
    inviter := new.user_a;
    new_connection := new.user_b;
  end if;

  select display_name into actor_name
  from public.profiles where id = new_connection;

  insert into public.notifications (
    recipient_id, actor_id, actor_name, kind, detail
  ) values (
    inviter, new_connection, coalesce(actor_name, 'Someone'),
    'connection_added', 'Accepted your invitation to connect'
  );
  return new;
end;
$$;

create trigger notify_on_connection_added
  after insert on public.connections
  for each row execute function private.notify_connection_added();

revoke all on function private.notify_photo_owner_of_glow()
  from public, anon, authenticated;
revoke all on function private.notify_gallery_member_change()
  from public, anon, authenticated;
revoke all on function private.notify_gallery_update()
  from public, anon, authenticated;
revoke all on function private.notify_connection_added()
  from public, anon, authenticated;

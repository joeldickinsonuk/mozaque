alter table public.notifications drop constraint if exists notifications_kind_check;
alter table public.notifications add constraint notifications_kind_check check (
  kind in (
    'glow', 'member_added', 'member_joined', 'member_role_changed',
    'gallery_preserved', 'gallery_settings_changed', 'connection_added',
    'photo_note', 'guestbook_message', 'guestbook_reply', 'connection_request'
  )
);
alter table public.notifications drop constraint if exists notifications_target_check;
alter table public.notifications add constraint notifications_target_check check (
  kind in ('connection_added', 'connection_request')
  or gallery_id is not null
  or photo_id is not null
);

create or replace function private.notify_connection_request()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.notifications(recipient_id, actor_id, actor_name, kind, detail)
  select new.recipient_id, new.requester_id, p.display_name,
         'connection_request', 'Would like to connect with you'
  from public.profiles p
  where p.id = new.requester_id;
  return new;
end;
$$;

create trigger notify_on_connection_request
after insert on public.connection_requests
for each row execute function private.notify_connection_request();

revoke all on function private.notify_connection_request() from public, anon, authenticated;

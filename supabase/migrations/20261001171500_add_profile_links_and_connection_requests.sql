alter table public.profiles add column profile_slug text;
create unique index profiles_profile_slug_unique on public.profiles(profile_slug) where profile_slug is not null;
alter table public.profiles add constraint profiles_profile_slug_format check (profile_slug is null or profile_slug ~ '^[a-z0-9][a-z0-9_-]{2,29}$');

create table private.profile_slug_reservations (slug text primary key, reserved_until timestamptz not null);
revoke all on private.profile_slug_reservations from public, anon, authenticated;

create or replace function private.reserve_old_profile_slug() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if old.profile_slug is not null and (tg_op = 'DELETE' or old.profile_slug is distinct from new.profile_slug) then
    insert into private.profile_slug_reservations(slug, reserved_until)
    values (old.profile_slug, now() + interval '30 days')
    on conflict (slug) do update set reserved_until = excluded.reserved_until;
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;
create trigger reserve_profile_slug_on_change
before update of profile_slug or delete on public.profiles
for each row execute function private.reserve_old_profile_slug();

create table public.connection_requests (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references public.profiles(id) on delete cascade,
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'accepted', 'declined')),
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  check (requester_id <> recipient_id)
);
create unique index connection_requests_one_pending_direction on public.connection_requests(requester_id, recipient_id) where status = 'pending';
create index connection_requests_recipient_pending on public.connection_requests(recipient_id, created_at desc) where status = 'pending';
alter table public.connection_requests enable row level security;
create policy connection_requests_read_own on public.connection_requests for select to authenticated
  using (requester_id = (select auth.uid()) or recipient_id = (select auth.uid()));
revoke all on public.connection_requests from public, anon, authenticated;
grant select on public.connection_requests to authenticated;

create or replace function private.can_view_profile(target_user uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select target_user = (select auth.uid())
    or private.are_connected(target_user)
    or exists (
      select 1 from public.gallery_members a
      join public.gallery_members b on a.gallery_id = b.gallery_id
      where a.user_id = (select auth.uid()) and b.user_id = target_user
    )
    or exists (
      select 1 from public.connection_requests r
      where r.status = 'pending'
        and ((r.requester_id = (select auth.uid()) and r.recipient_id = target_user)
          or (r.recipient_id = (select auth.uid()) and r.requester_id = target_user))
    );
$$;

create or replace function public.lookup_profile_slug(target_slug text)
returns table(profile_id uuid, profile_slug text, display_name text, avatar_path text)
language sql stable security definer set search_path = '' as $$
  select p.id, p.profile_slug, p.display_name, p.avatar_path
  from public.profiles p
  where p.profile_slug = lower(trim(both '@' from trim(target_slug)))
  limit 1;
$$;

create or replace function public.set_my_profile_slug(requested_slug text) returns text
language plpgsql security definer set search_path = '' as $$
declare
  clean_slug text := lower(trim(both '@' from trim(coalesce(requested_slug, ''))));
begin
  if (select auth.uid()) is null then raise exception 'Sign in to set your Mozaque link.'; end if;
  if clean_slug = '' then
    update public.profiles set profile_slug = null where id = (select auth.uid());
    if not found then raise exception 'Your profile is not ready yet. Please try again.'; end if;
    return null;
  end if;
  if clean_slug !~ '^[a-z0-9][a-z0-9_-]{2,29}$' then
    raise exception 'Use 3–30 letters, numbers, underscores or hyphens. Start with a letter or number.';
  end if;
  if clean_slug = any(array['feed','people','settings','auth','invite','privacy','terms','profile','mozaques','pieces','login','signup','join','about']) then
    raise exception 'That link name is reserved. Please choose another.';
  end if;
  if exists (select 1 from private.profile_slug_reservations r where r.slug = clean_slug and r.reserved_until > now())
     and not exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.profile_slug = clean_slug) then
    raise exception 'That link was used recently and is held for privacy. Choose another.';
  end if;
  update public.profiles set profile_slug = clean_slug where id = (select auth.uid());
  if not found then raise exception 'Your profile is not ready yet. Please try again.'; end if;
  return clean_slug;
exception when unique_violation then
  raise exception 'That link is already being used. Please choose another.';
end;
$$;

create or replace function public.request_connection_by_slug(target_slug text) returns text
language plpgsql security definer set search_path = '' as $$
declare
  caller uuid := (select auth.uid());
  target uuid;
  pending_id uuid;
begin
  if caller is null then raise exception 'Sign in to send a connection request.'; end if;
  select p.id into target from public.profiles p
    where p.profile_slug = lower(trim(both '@' from trim(target_slug)));
  if target is null then raise exception 'This Mozaque link is no longer available.'; end if;
  if target = caller then raise exception 'That is your own Mozaque link.'; end if;
  if private.are_connected(target) then return 'connected'; end if;
  select r.id into pending_id from public.connection_requests r
    where r.requester_id = target and r.recipient_id = caller and r.status = 'pending' for update;
  if pending_id is not null then
    update public.connection_requests set status = 'accepted', responded_at = now()
      where id = pending_id and recipient_id = caller;
    insert into public.connections(user_a, user_b) values (least(caller, target), greatest(caller, target)) on conflict do nothing;
    return 'connected';
  end if;
  if exists (select 1 from public.connection_requests r where r.requester_id = caller and r.recipient_id = target and r.status = 'pending') then return 'pending'; end if;
  if exists (select 1 from public.connection_requests r where r.requester_id = caller and r.recipient_id = target and r.status = 'declined' and r.responded_at > now() - interval '30 days') then
    raise exception 'This person recently declined a request. Please respect their choice.';
  end if;
  if (select count(*) from public.connection_requests r where r.requester_id = caller and r.created_at > now() - interval '24 hours') >= 10 then
    raise exception 'You’ve sent several requests today. Try again tomorrow.';
  end if;
  insert into public.connection_requests(requester_id, recipient_id) values (caller, target);
  return 'pending';
end;
$$;

create or replace function public.respond_to_connection_request(request_id uuid, accept_request boolean) returns text
language plpgsql security definer set search_path = '' as $$
declare
  caller uuid := (select auth.uid());
  sender uuid;
begin
  if caller is null then raise exception 'Sign in to respond to this request.'; end if;
  select r.requester_id into sender from public.connection_requests r
    where r.id = request_id and r.recipient_id = caller and r.status = 'pending' for update;
  if sender is null then raise exception 'This request is no longer waiting for a reply.'; end if;
  update public.connection_requests
    set status = case when accept_request then 'accepted' else 'declined' end, responded_at = now()
    where id = request_id and recipient_id = caller and status = 'pending';
  if accept_request then
    insert into public.connections(user_a, user_b) values (least(caller, sender), greatest(caller, sender)) on conflict do nothing;
    return 'connected';
  end if;
  return 'declined';
end;
$$;

revoke update on public.profiles from authenticated;
grant update(display_name, avatar_path) on public.profiles to authenticated;
revoke all on function private.reserve_old_profile_slug() from public, anon, authenticated;
revoke all on function public.lookup_profile_slug(text) from public, anon, authenticated;
revoke all on function public.set_my_profile_slug(text) from public, anon, authenticated;
revoke all on function public.request_connection_by_slug(text) from public, anon, authenticated;
revoke all on function public.respond_to_connection_request(uuid, boolean) from public, anon, authenticated;
grant execute on function public.lookup_profile_slug(text) to anon, authenticated;
grant execute on function public.set_my_profile_slug(text) to authenticated;
grant execute on function public.request_connection_by_slug(text) to authenticated;
grant execute on function public.respond_to_connection_request(uuid, boolean) to authenticated;

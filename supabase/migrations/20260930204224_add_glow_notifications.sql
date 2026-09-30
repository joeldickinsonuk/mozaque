create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  actor_id uuid not null references public.profiles(id) on delete cascade,
  actor_name text not null,
  kind text not null check (kind = 'glow'),
  photo_id uuid not null references public.photos(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (recipient_id, actor_id, kind, photo_id)
);

create index notifications_recipient_created
  on public.notifications(recipient_id, created_at desc);

alter table public.notifications enable row level security;

create policy notifications_read_own
  on public.notifications for select to authenticated
  using ((select auth.uid()) = recipient_id);

grant select on public.notifications to authenticated;

create or replace function private.notify_photo_owner_of_glow()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.notifications (
    recipient_id, actor_id, actor_name, kind, photo_id
  )
  select p.uploader_id, new.user_id, pr.display_name, 'glow', p.id
  from public.photos p
  join public.profiles pr on pr.id = new.user_id
  where p.id = new.photo_id
    and p.uploader_id <> new.user_id
  on conflict (recipient_id, actor_id, kind, photo_id) do nothing;
  return new;
end;
$$;

revoke all on function private.notify_photo_owner_of_glow()
  from public, anon, authenticated;

create trigger notify_photo_owner_after_glow
  after insert on public.glows
  for each row execute function private.notify_photo_owner_of_glow();

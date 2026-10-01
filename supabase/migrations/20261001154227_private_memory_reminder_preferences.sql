alter table public.profiles
  drop column if exists memory_reminders_enabled;

create table public.user_preferences (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  memory_reminders_enabled boolean not null default true,
  updated_at timestamptz not null default now()
);

alter table public.user_preferences enable row level security;

create policy user_preferences_read_own
  on public.user_preferences for select to authenticated
  using (user_id = (select auth.uid()));

create policy user_preferences_create_own
  on public.user_preferences for insert to authenticated
  with check (user_id = (select auth.uid()));

create policy user_preferences_update_own
  on public.user_preferences for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

grant select, insert, update on public.user_preferences to authenticated;

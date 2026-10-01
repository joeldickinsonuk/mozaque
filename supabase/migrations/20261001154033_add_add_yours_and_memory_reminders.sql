alter table public.galleries
  add column add_yours_prompt text
    check (add_yours_prompt is null or char_length(trim(add_yours_prompt)) between 1 and 140);

alter table public.profiles
  add column memory_reminders_enabled boolean not null default true;

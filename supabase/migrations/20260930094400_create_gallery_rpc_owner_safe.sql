-- Create galleries using the authenticated database identity rather than a
-- client-supplied owner_id. Keep the privileged insert helper in the private
-- schema and expose only the constrained operation to signed-in callers.
create or replace function private.insert_mozaque_gallery(
  p_title text,
  p_description text,
  p_event_type text,
  p_event_date date,
  p_is_recurring boolean,
  p_upload_policy text,
  p_audience text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
  created_gallery public.galleries;
begin
  if caller_id is null then
    raise exception using
      errcode = '42501',
      message = 'A signed-in account is required to create a Mozaque.';
  end if;

  insert into public.galleries (
    owner_id,
    title,
    description,
    event_type,
    event_date,
    is_recurring,
    upload_policy,
    audience
  ) values (
    caller_id,
    p_title,
    coalesce(p_description, ''),
    p_event_type,
    p_event_date,
    coalesce(p_is_recurring, false),
    p_upload_policy,
    p_audience
  )
  returning * into created_gallery;

  return to_jsonb(created_gallery);
end;
$$;

revoke all on function private.insert_mozaque_gallery(text,text,text,date,boolean,text,text)
  from public, anon, authenticated;
grant execute on function private.insert_mozaque_gallery(text,text,text,date,boolean,text,text)
  to authenticated;

create or replace function public.create_gallery(
  p_title text,
  p_description text,
  p_event_type text,
  p_event_date date,
  p_is_recurring boolean,
  p_upload_policy text,
  p_audience text
) returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select private.insert_mozaque_gallery(
    p_title,
    p_description,
    p_event_type,
    p_event_date,
    p_is_recurring,
    p_upload_policy,
    p_audience
  );
$$;

revoke all on function public.create_gallery(text,text,text,date,boolean,text,text)
  from public, anon, authenticated;
grant execute on function public.create_gallery(text,text,text,date,boolean,text,text)
  to authenticated;

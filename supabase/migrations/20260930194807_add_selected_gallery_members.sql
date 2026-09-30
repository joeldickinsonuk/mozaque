-- Allow an owner to add only their existing connections to an invite-only,
-- open Mozaque. Keep the privileged insert in the private schema and expose
-- only this constrained RPC to signed-in users.
create or replace function private.insert_connected_gallery_member(
  target_gallery uuid,
  target_user uuid
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := auth.uid();
begin
  if caller_id is null then
    raise exception using
      errcode = '42501',
      message = 'A signed-in account is required to add people.';
  end if;

  if target_user = caller_id then
    raise exception 'You are already part of your own Mozaque.';
  end if;

  if not exists (
    select 1
    from public.galleries g
    where g.id = target_gallery
      and g.owner_id = caller_id
      and g.audience = 'invited'
      and g.frozen_at is null
  ) then
    raise exception using
      errcode = '42501',
      message = 'Only the owner can add people to an open invite-only Mozaque.';
  end if;

  if not exists (
    select 1
    from public.connections c
    where (c.user_a = caller_id and c.user_b = target_user)
       or (c.user_b = caller_id and c.user_a = target_user)
  ) then
    raise exception using
      errcode = '42501',
      message = 'You can only add people in your circle.';
  end if;

  insert into public.gallery_members (gallery_id, user_id, role)
  values (target_gallery, target_user, 'viewer')
  on conflict (gallery_id, user_id) do nothing;
end;
$$;

create or replace function public.add_connection_to_gallery(
  target_gallery uuid,
  target_user uuid
) returns void
language sql
security invoker
set search_path = ''
as $$
  select private.insert_connected_gallery_member(target_gallery, target_user);
$$;

revoke all on function private.insert_connected_gallery_member(uuid, uuid)
  from public, anon, authenticated;
grant execute on function private.insert_connected_gallery_member(uuid, uuid)
  to authenticated;
revoke all on function public.add_connection_to_gallery(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.add_connection_to_gallery(uuid, uuid)
  to authenticated;

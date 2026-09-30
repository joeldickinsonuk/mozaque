create extension if not exists pgcrypto;

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
grant usage on schema private to authenticated;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 60),
  created_at timestamptz not null default now()
);
create or replace function private.create_mozaque_profile() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 insert into public.profiles(id,display_name) values(new.id,coalesce(nullif(trim(new.raw_user_meta_data->>'display_name'),''),split_part(new.email,'@',1)));
 return new;
end $$;
create trigger on_auth_user_created_mozaque after insert on auth.users for each row execute procedure private.create_mozaque_profile();

create table public.connections (
  user_a uuid not null references public.profiles(id) on delete cascade,
  user_b uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(user_a,user_b), check (user_a < user_b)
);
create table public.galleries (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  title text not null check (char_length(title) between 1 and 100),
  description text not null default '' check (char_length(description) <= 1000),
  event_type text not null check (event_type in ('everyday','birthday','wedding','christmas','anniversary','holiday','other')),
  event_date date not null,
  is_recurring boolean not null default false,
  audience text not null default 'invited' check (audience in ('invited','connections')),
  upload_policy text not null default 'everyone' check (upload_policy in ('owner','selected','everyone')),
  frozen_at timestamptz,
  created_at timestamptz not null default now()
);
create table public.gallery_members (
  gallery_id uuid not null references public.galleries(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role text not null default 'viewer' check(role in ('viewer','contributor')),
  created_at timestamptz not null default now(),
  primary key(gallery_id,user_id)
);
create table public.gallery_invites (
  id uuid primary key default gen_random_uuid(),
  token_hash text not null unique,
  created_by uuid not null references public.profiles(id) on delete cascade,
  gallery_id uuid references public.galleries(id) on delete cascade,
  kind text not null check(kind in ('gallery','connection')),
  expires_at timestamptz not null default now() + interval '7 days',
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  check ((kind='gallery' and gallery_id is not null) or (kind='connection' and gallery_id is null))
);
create table public.photos (
  id uuid primary key default gen_random_uuid(),
  gallery_id uuid not null references public.galleries(id) on delete cascade,
  uploader_id uuid not null references public.profiles(id) on delete cascade,
  storage_path text not null unique,
  caption text not null default '' check(char_length(caption) <= 500),
  mime_type text not null check(mime_type in ('image/jpeg','image/png','image/webp')),
  byte_size integer not null check(byte_size between 1 and 10485760),
  created_at timestamptz not null default now()
);
create table public.pieces (
  user_id uuid not null references public.profiles(id) on delete cascade,
  photo_id uuid not null references public.photos(id) on delete cascade,
  created_at timestamptz not null default now(), primary key(user_id,photo_id)
);
create table public.glows (
  user_id uuid not null references public.profiles(id) on delete cascade,
  photo_id uuid not null references public.photos(id) on delete cascade,
  created_at timestamptz not null default now(), primary key(user_id,photo_id)
);
create index galleries_owner_date on public.galleries(owner_id,created_at desc);
create index gallery_members_user on public.gallery_members(user_id,gallery_id);
create index photos_gallery_date on public.photos(gallery_id,created_at desc);
create index invites_gallery on public.gallery_invites(gallery_id) where revoked_at is null;

create or replace function private.are_connected(other_user uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.connections c where (c.user_a=auth.uid() and c.user_b=other_user) or (c.user_b=auth.uid() and c.user_a=other_user));
$$;
create or replace function private.can_view_gallery(target_gallery uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.galleries g where g.id=target_gallery and (g.owner_id=auth.uid() or exists(select 1 from public.gallery_members m where m.gallery_id=g.id and m.user_id=auth.uid()) or (g.audience='connections' and private.are_connected(g.owner_id))));
$$;
create or replace function private.can_upload_gallery(target_gallery uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.galleries g where g.id=target_gallery and g.frozen_at is null and (
   g.owner_id=auth.uid() or
   (g.upload_policy='everyone' and (exists(select 1 from public.gallery_members m where m.gallery_id=g.id and m.user_id=auth.uid()) or (g.audience='connections' and private.are_connected(g.owner_id)))) or
   (g.upload_policy='selected' and exists(select 1 from public.gallery_members m where m.gallery_id=g.id and m.user_id=auth.uid() and m.role='contributor'))
 ));
$$;
create or replace function private.can_delete_gallery_photo(target_gallery uuid, target_uploader uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.galleries g where g.id=target_gallery and g.frozen_at is null and (g.owner_id=auth.uid() or target_uploader=auth.uid()));
$$;
create or replace function private.can_view_profile(target_user uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select target_user=auth.uid() or private.are_connected(target_user) or exists(
  select 1 from public.gallery_members a join public.gallery_members b on a.gallery_id=b.gallery_id where a.user_id=auth.uid() and b.user_id=target_user
 );
$$;
create or replace function public.freeze_gallery(target_gallery uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
 update public.galleries set frozen_at=now() where id=target_gallery and owner_id=auth.uid() and frozen_at is null;
 if not found then raise exception 'This Mozaque cannot be preserved.'; end if;
end $$;
create or replace function public.set_gallery_member_role(target_gallery uuid,target_user uuid,target_role text) returns void
language plpgsql security definer set search_path='' as $$
begin
 if target_role not in ('viewer','contributor') then raise exception 'Invalid role.'; end if;
 update public.gallery_members m set role=target_role from public.galleries g where m.gallery_id=target_gallery and m.user_id=target_user and g.id=m.gallery_id and g.owner_id=auth.uid() and g.frozen_at is null;
 if not found then raise exception 'This member role cannot be changed.'; end if;
end $$;
create or replace function public.accept_invite(invite_hash text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare i public.gallery_invites%rowtype; a uuid; b uuid;
begin
 select * into i from public.gallery_invites where token_hash=invite_hash and revoked_at is null and expires_at>now() for update;
 if not found then raise exception 'This invitation has expired or was revoked.'; end if;
 if i.created_by=auth.uid() then raise exception 'You cannot accept your own invitation.'; end if;
 if i.kind='gallery' then
  insert into public.gallery_members(gallery_id,user_id,role) values(i.gallery_id,auth.uid(),'viewer') on conflict do nothing;
  return jsonb_build_object('kind','gallery','gallery_id',i.gallery_id);
 end if;
 a:=least(auth.uid(),i.created_by); b:=greatest(auth.uid(),i.created_by);
 insert into public.connections(user_a,user_b) values(a,b) on conflict do nothing;
 return jsonb_build_object('kind','connection');
end $$;
create or replace function public.create_gallery_invite(target_gallery uuid, invite_hash text) returns timestamptz
language plpgsql security definer set search_path='' as $$
declare expiry timestamptz:=now()+interval '7 days';
begin
 if not exists(select 1 from public.galleries where id=target_gallery and owner_id=auth.uid() and frozen_at is null) then raise exception 'Only the owner can invite people to an open Mozaque.'; end if;
 insert into public.gallery_invites(token_hash,created_by,gallery_id,kind,expires_at) values(invite_hash,auth.uid(),target_gallery,'gallery',expiry);
 return expiry;
end $$;
create or replace function public.create_connection_invite(invite_hash text) returns timestamptz
language plpgsql security definer set search_path='' as $$
declare expiry timestamptz:=now()+interval '7 days';
begin
 insert into public.gallery_invites(token_hash,created_by,kind,expires_at) values(invite_hash,auth.uid(),'connection',expiry);
 return expiry;
end $$;
create or replace function public.revoke_gallery_invite(invite_id uuid) returns void
language plpgsql security definer set search_path='' as $$
begin update public.gallery_invites set revoked_at=now() where id=invite_id and created_by=auth.uid() and revoked_at is null; end $$;

alter table public.profiles enable row level security;
alter table public.connections enable row level security;
alter table public.galleries enable row level security;
alter table public.gallery_members enable row level security;
alter table public.gallery_invites enable row level security;
alter table public.photos enable row level security;
alter table public.pieces enable row level security;
alter table public.glows enable row level security;
create policy profiles_read on public.profiles for select to authenticated using(private.can_view_profile(id));
create policy profiles_update on public.profiles for update to authenticated using(id=auth.uid()) with check(id=auth.uid());
create policy connections_read on public.connections for select to authenticated using(user_a=auth.uid() or user_b=auth.uid());
create policy galleries_read on public.galleries for select to authenticated using(private.can_view_gallery(id));
create policy galleries_create on public.galleries for insert to authenticated with check(owner_id=auth.uid());
create policy galleries_edit on public.galleries for update to authenticated using(owner_id=auth.uid() and frozen_at is null) with check(owner_id=auth.uid() and frozen_at is null);
create policy members_read on public.gallery_members for select to authenticated using(private.can_view_gallery(gallery_id));
create policy photos_read on public.photos for select to authenticated using(private.can_view_gallery(gallery_id));
create policy photos_create on public.photos for insert to authenticated with check(uploader_id=auth.uid() and private.can_upload_gallery(gallery_id));
create policy photos_remove on public.photos for delete to authenticated using(private.can_delete_gallery_photo(gallery_id,uploader_id));
create policy pieces_read on public.pieces for select to authenticated using(user_id=auth.uid() and exists(select 1 from public.photos p where p.id=photo_id and private.can_view_gallery(p.gallery_id)));
create policy pieces_create on public.pieces for insert to authenticated with check(user_id=auth.uid() and exists(select 1 from public.photos p where p.id=photo_id and private.can_view_gallery(p.gallery_id)));
create policy pieces_remove on public.pieces for delete to authenticated using(user_id=auth.uid());
create policy glows_read on public.glows for select to authenticated using(private.can_view_gallery((select p.gallery_id from public.photos p where p.id=photo_id)));
create policy glows_create on public.glows for insert to authenticated with check(user_id=auth.uid() and exists(select 1 from public.photos p where p.id=photo_id and private.can_view_gallery(p.gallery_id)));
create policy glows_remove on public.glows for delete to authenticated using(user_id=auth.uid());
create policy invites_read on public.gallery_invites for select to authenticated using(created_by=auth.uid());
create policy invites_create on public.gallery_invites for insert to authenticated with check(false);


insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('mozaque-photos','mozaque-photos',false,10485760,array['image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=false,file_size_limit=10485760,allowed_mime_types=array['image/jpeg','image/png','image/webp'];
create policy mozaque_photos_read on storage.objects for select to authenticated using(bucket_id='mozaque-photos' and private.can_view_gallery((storage.foldername(name))[1]::uuid));
create policy mozaque_photos_upload on storage.objects for insert to authenticated with check(bucket_id='mozaque-photos' and private.can_upload_gallery((storage.foldername(name))[1]::uuid) and (storage.foldername(name))[2]=auth.uid()::text);
create policy mozaque_photos_delete on storage.objects for delete to authenticated using(bucket_id='mozaque-photos' and private.can_delete_gallery_photo((storage.foldername(name))[1]::uuid,((storage.foldername(name))[2])::uuid));

-- Keep trigger and policy helpers out of the exposed public schema. Only
-- authenticated users need helper execution for RLS and storage policies.
revoke all on function private.create_mozaque_profile() from public, anon, authenticated;
revoke all on function private.are_connected(uuid) from public, anon, authenticated;
revoke all on function private.can_view_gallery(uuid) from public, anon, authenticated;
revoke all on function private.can_upload_gallery(uuid) from public, anon, authenticated;
revoke all on function private.can_delete_gallery_photo(uuid,uuid) from public, anon, authenticated;
revoke all on function private.can_view_profile(uuid) from public, anon, authenticated;
grant execute on function private.are_connected(uuid) to authenticated;
grant execute on function private.can_view_gallery(uuid) to authenticated;
grant execute on function private.can_upload_gallery(uuid) to authenticated;
grant execute on function private.can_delete_gallery_photo(uuid,uuid) to authenticated;
grant execute on function private.can_view_profile(uuid) to authenticated;

-- These SECURITY DEFINER RPCs are intentional app entry points. Limit them
-- to signed-in users; their function bodies also validate the caller's rights.
revoke all on function public.accept_invite(text) from public, anon, authenticated;
revoke all on function public.create_gallery_invite(uuid,text) from public, anon, authenticated;
revoke all on function public.create_connection_invite(text) from public, anon, authenticated;
revoke all on function public.revoke_gallery_invite(uuid) from public, anon, authenticated;
revoke all on function public.freeze_gallery(uuid) from public, anon, authenticated;
revoke all on function public.set_gallery_member_role(uuid,uuid,text) from public, anon, authenticated;
grant execute on function public.accept_invite(text) to authenticated;
grant execute on function public.create_gallery_invite(uuid,text) to authenticated;
grant execute on function public.create_connection_invite(text) to authenticated;
grant execute on function public.revoke_gallery_invite(uuid) to authenticated;
grant execute on function public.freeze_gallery(uuid) to authenticated;
grant execute on function public.set_gallery_member_role(uuid,uuid,text) to authenticated;

-- RLS is the data boundary; grants only expose the operations described by the policies.
grant usage on schema public to authenticated;
grant select on public.profiles,public.connections,public.galleries,public.gallery_members,public.gallery_invites,public.photos,public.pieces,public.glows to authenticated;
grant update on public.profiles,public.galleries to authenticated;
grant insert on public.galleries,public.photos,public.pieces,public.glows to authenticated;
grant delete on public.photos,public.pieces,public.glows to authenticated;

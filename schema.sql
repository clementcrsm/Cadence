-- ============================================================
-- Cadence v1 : schéma Supabase
-- À exécuter une seule fois : Supabase > SQL Editor > New query > coller > Run
-- ============================================================

create extension if not exists pgcrypto;

-- ---------- Tables ----------
create table if not exists public.profiles (
  id uuid primary key references auth.users on delete cascade,
  display_name text not null default '',
  settings jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.workspaces (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 80),
  kind text not null default 'team' check (kind in ('personal','team')),
  owner_id uuid not null references auth.users on delete cascade,
  invite_code text unique not null default upper(substr(md5(gen_random_uuid()::text), 1, 6)),
  settings jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.workspace_members (
  workspace_id uuid not null references public.workspaces on delete cascade,
  user_id uuid not null references auth.users on delete cascade,
  role text not null default 'editor' check (role in ('owner','editor','viewer')),
  joined_at timestamptz not null default now(),
  primary key (workspace_id, user_id)
);

create table if not exists public.campaigns (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces on delete cascade,
  name text not null,
  kind text not null default 'campagne' check (kind in ('campagne','temps_fort')),
  color text not null default '#F5D547',
  start_date date not null,
  end_date date not null check (end_date >= start_date),
  description text,
  created_by uuid default auth.uid() references auth.users on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.posts (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces on delete cascade,
  created_by uuid default auth.uid() references auth.users on delete set null,
  title text not null default '',
  body text default '',
  channel text,
  format text,
  status text not null default 'idee' check (status in ('idee','redaction','a_valider','programme','publie')),
  pub_date date,
  pub_time time,
  labels text[] not null default '{}',
  campaign_id uuid references public.campaigns on delete set null,
  media_path text,
  link text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.day_marks (
  workspace_id uuid not null references public.workspaces on delete cascade,
  day date not null,
  type text not null check (type in ('formation','entreprise','ferie','examen','vacances')),
  primary key (workspace_id, day)
);

create table if not exists public.saved_views (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces on delete cascade,
  user_id uuid not null default auth.uid() references auth.users on delete cascade,
  name text not null,
  filters jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists posts_ws_date on public.posts (workspace_id, pub_date);
create index if not exists campaigns_ws on public.campaigns (workspace_id, start_date);
create index if not exists members_user on public.workspace_members (user_id);

-- ---------- Fonctions utilitaires (contournent la récursion RLS) ----------
create or replace function public.ws_role(ws uuid) returns text
language sql stable security definer set search_path = public as $$
  select role from public.workspace_members where workspace_id = ws and user_id = auth.uid()
$$;

create or replace function public.is_member(ws uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.workspace_members where workspace_id = ws and user_id = auth.uid())
$$;

create or replace function public.can_edit(ws uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.ws_role(ws) in ('owner','editor'), false)
$$;

create or replace function public.shares_workspace(other uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.workspace_members a
    join public.workspace_members b on a.workspace_id = b.workspace_id
    where a.user_id = auth.uid() and b.user_id = other
  )
$$;

create or replace function public.touch_updated_at() returns trigger
language plpgsql as $$ begin new.updated_at = now(); return new; end $$;

drop trigger if exists posts_touch on public.posts;
create trigger posts_touch before update on public.posts for each row execute function public.touch_updated_at();
drop trigger if exists campaigns_touch on public.campaigns;
create trigger campaigns_touch before update on public.campaigns for each row execute function public.touch_updated_at();

-- ---------- Inscription : profil + espace personnel automatiques ----------
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare ws uuid;
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(nullif(new.raw_user_meta_data->>'display_name', ''), split_part(new.email, '@', 1)));
  insert into public.workspaces (name, kind, owner_id) values ('Mon calendrier', 'personal', new.id) returning id into ws;
  insert into public.workspace_members (workspace_id, user_id, role) values (ws, new.id, 'owner');
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

-- ---------- Création et adhésion aux espaces d'équipe ----------
create or replace function public.create_workspace(p_name text) returns public.workspaces
language plpgsql security definer set search_path = public as $$
declare w public.workspaces;
begin
  if auth.uid() is null then raise exception 'non_connecte'; end if;
  insert into public.workspaces (name, kind, owner_id) values (trim(p_name), 'team', auth.uid()) returning * into w;
  insert into public.workspace_members (workspace_id, user_id, role) values (w.id, auth.uid(), 'owner');
  return w;
end $$;

create or replace function public.join_workspace(p_code text) returns uuid
language plpgsql security definer set search_path = public as $$
declare ws uuid;
begin
  if auth.uid() is null then raise exception 'non_connecte'; end if;
  select id into ws from public.workspaces where invite_code = upper(trim(p_code)) and kind = 'team';
  if ws is null then raise exception 'code_invalide'; end if;
  insert into public.workspace_members (workspace_id, user_id, role) values (ws, auth.uid(), 'editor')
  on conflict (workspace_id, user_id) do nothing;
  return ws;
end $$;

revoke all on function public.create_workspace(text) from anon;
revoke all on function public.join_workspace(text) from anon;

-- ---------- Sécurité par ligne (RLS) ----------
alter table public.profiles enable row level security;
alter table public.workspaces enable row level security;
alter table public.workspace_members enable row level security;
alter table public.campaigns enable row level security;
alter table public.posts enable row level security;
alter table public.day_marks enable row level security;
alter table public.saved_views enable row level security;

-- profils : chacun voit le sien et ceux des membres de ses espaces
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles for select to authenticated
  using (id = auth.uid() or public.shares_workspace(id));
drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

-- espaces
drop policy if exists ws_select on public.workspaces;
create policy ws_select on public.workspaces for select to authenticated using (public.is_member(id));
drop policy if exists ws_update on public.workspaces;
create policy ws_update on public.workspaces for update to authenticated
  using (public.ws_role(id) = 'owner') with check (public.ws_role(id) = 'owner');
drop policy if exists ws_delete on public.workspaces;
create policy ws_delete on public.workspaces for delete to authenticated
  using (public.ws_role(id) = 'owner' and kind = 'team');

-- membres
drop policy if exists wm_select on public.workspace_members;
create policy wm_select on public.workspace_members for select to authenticated using (public.is_member(workspace_id));
drop policy if exists wm_update on public.workspace_members;
create policy wm_update on public.workspace_members for update to authenticated
  using (public.ws_role(workspace_id) = 'owner' and user_id <> auth.uid())
  with check (role in ('editor','viewer'));
drop policy if exists wm_delete on public.workspace_members;
create policy wm_delete on public.workspace_members for delete to authenticated
  using ((user_id = auth.uid() and role <> 'owner') or (public.ws_role(workspace_id) = 'owner' and user_id <> auth.uid()));

-- contenus, campagnes, calque alternance : lecture pour les membres, écriture pour propriétaire et éditeurs
do $$
declare t text;
begin
  foreach t in array array['posts','campaigns','day_marks'] loop
    execute format('drop policy if exists %1$s_select on public.%1$s', t);
    execute format('create policy %1$s_select on public.%1$s for select to authenticated using (public.is_member(workspace_id))', t);
    execute format('drop policy if exists %1$s_insert on public.%1$s', t);
    execute format('create policy %1$s_insert on public.%1$s for insert to authenticated with check (public.can_edit(workspace_id))', t);
    execute format('drop policy if exists %1$s_update on public.%1$s', t);
    execute format('create policy %1$s_update on public.%1$s for update to authenticated using (public.can_edit(workspace_id)) with check (public.can_edit(workspace_id))', t);
    execute format('drop policy if exists %1$s_delete on public.%1$s', t);
    execute format('create policy %1$s_delete on public.%1$s for delete to authenticated using (public.can_edit(workspace_id))', t);
  end loop;
end $$;

-- vues enregistrées : strictement personnelles
drop policy if exists sv_all on public.saved_views;
create policy sv_all on public.saved_views for all to authenticated
  using (user_id = auth.uid() and public.is_member(workspace_id))
  with check (user_id = auth.uid() and public.is_member(workspace_id));

-- ---------- Stockage des visuels (bucket privé) ----------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('media', 'media', false, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;

drop policy if exists media_read on storage.objects;
create policy media_read on storage.objects for select to authenticated
  using (bucket_id = 'media' and public.is_member(((storage.foldername(name))[1])::uuid));
drop policy if exists media_insert on storage.objects;
create policy media_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'media' and public.can_edit(((storage.foldername(name))[1])::uuid));
drop policy if exists media_delete on storage.objects;
create policy media_delete on storage.objects for delete to authenticated
  using (bucket_id = 'media' and public.can_edit(((storage.foldername(name))[1])::uuid));

-- ---------- Temps réel (mises à jour en direct dans les espaces d'équipe) ----------
alter table public.posts replica identity full;
alter table public.campaigns replica identity full;
alter table public.day_marks replica identity full;
do $$
begin
  begin alter publication supabase_realtime add table public.posts; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.campaigns; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.day_marks; exception when duplicate_object then null; end;
end $$;

-- Reindeer Games: Supabase setup
-- Paste this whole file into Supabase > SQL Editor > New query, then click Run.
-- Safe to run again: it drops and recreates its own policies and functions.
--
-- AFTER running it, add yourself as the organizer (replace the email):
--   insert into public.organizers (email) values ('you@example.com');

create extension if not exists pgcrypto;

-- ============ tables ============
create table if not exists public.organizers (
  email text primary key
);

create table if not exists public.config (
  id int primary key default 1 check (id = 1),
  data jsonb not null default '{}'::jsonb
);
insert into public.config (id, data) values (1, '{}'::jsonb) on conflict do nothing;

create table if not exists public.homes (
  id uuid primary key default gen_random_uuid(),
  family text not null check (char_length(family) between 1 and 60),
  number text not null check (char_length(number) between 1 and 10),
  x double precision,
  y double precision,
  owner_id uuid references auth.users(id) on delete set null,
  created_at bigint not null default (extract(epoch from clock_timestamp()) * 1000)::bigint
);

create table if not exists public.joins (
  user_id uuid primary key default auth.uid() references auth.users(id) on delete cascade,
  family text not null check (char_length(family) between 1 and 60),
  number text not null check (char_length(number) between 1 and 10),
  x double precision,
  y double precision,
  status text not null default 'pending' check (status in ('pending','approved','declined')),
  at timestamptz not null default now()
);

create table if not exists public.steals (
  id uuid primary key default gen_random_uuid(),
  season text not null,
  kind text not null default 'steal' check (kind in ('steal','start')),
  from_home uuid references public.homes(id) on delete set null,
  to_home uuid references public.homes(id) on delete set null,
  at timestamptz not null default now(),
  note text not null default '' check (char_length(note) <= 200),
  by_user uuid default auth.uid(),
  created_at bigint not null default (extract(epoch from clock_timestamp()) * 1000)::bigint
);
create index if not exists steals_season_at on public.steals (season, at desc, created_at desc);

create table if not exists public.media (
  id uuid primary key default gen_random_uuid(),
  steal_id uuid not null references public.steals(id) on delete cascade,
  path text not null unique,
  type text not null check (type in ('image','video')),
  by_user uuid default auth.uid(),
  by_home uuid references public.homes(id) on delete set null,
  at timestamptz not null default now()
);

-- ============ helper functions ============
create or replace function public.is_org() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from organizers
                 where lower(email) = lower(coalesce(auth.jwt() ->> 'email', '')));
$$;

create or replace function public.is_member() returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_org() or exists (select 1 from homes where owner_id = auth.uid());
$$;

-- The current game year. December game; January still counts as last year's game.
create or replace function public.current_season() returns text
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select data ->> 'current' from config where id = 1),
    to_char((now() at time zone 'America/Los_Angeles') - interval '1 month', 'YYYY')
  );
$$;

-- The secret rule: the newest steal of the current game (once the thief is known)
-- is hidden from everyone except the organizer and the two families involved,
-- until Rudolph is stolen again.
create or replace function public.steal_visible(
  s_id uuid, s_season text, s_from uuid, s_to uuid, s_by uuid, s_at timestamptz, s_created bigint
) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_org()
      or s_to is null
      or s_season <> public.current_season()
      or s_by = auth.uid()
      or exists (select 1 from homes h where h.owner_id = auth.uid() and h.id in (s_from, s_to))
      or exists (select 1 from steals t
                 where t.season = s_season and t.id <> s_id
                   and (t.at > s_at or (t.at = s_at and t.created_at > s_created)));
$$;

-- Tells members that a sealed steal exists (time only, never where).
create or replace function public.season_latest(p_season text)
returns table (id uuid, at timestamptz, created_at bigint)
language sql stable security definer set search_path = public as $$
  select s.id, s.at, s.created_at from steals s
  where public.is_member() and s.season = p_season
  order by s.at desc, s.created_at desc limit 1;
$$;

-- Log a steal. If the other family already logged the same steal, attach to it.
create or replace function public.log_steal(
  p_from uuid, p_to uuid, p_at timestamptz, p_note text default '', p_season text default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_season text := public.current_season();
  v_id uuid;
  v_to uuid;
begin
  if not public.is_member() then raise exception 'not a participant'; end if;
  if p_from is null then raise exception 'missing family'; end if;
  if public.is_org() and p_season is not null then v_season := p_season; end if;
  if not public.is_org() and not exists (
       select 1 from homes where owner_id = auth.uid() and id in (p_from, p_to)) then
    raise exception 'you can only log steals involving your family';
  end if;
  select id, to_home into v_id, v_to from steals
   where season = v_season and kind = 'steal' and from_home = p_from
     and (to_home = p_to or (p_to is null and to_home is not null) or (to_home is null and p_to is not null))
     and abs(extract(epoch from (at - p_at))) < 72 * 3600
   order by at desc limit 1;
  if v_id is not null then
    if v_to is null and p_to is not null then
      update steals set to_home = p_to, at = p_at where id = v_id;
    end if;
    return v_id;
  end if;
  insert into steals (season, kind, from_home, to_home, at, note, by_user)
  values (v_season, 'steal', p_from, p_to, p_at, left(coalesce(p_note, ''), 200), auth.uid())
  returning id into v_id;
  return v_id;
end;
$$;

-- "It was us": the thief claims a steal the other family reported.
create or replace function public.claim_steal(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_home uuid;
begin
  select id into v_home from homes where owner_id = auth.uid() limit 1;
  if v_home is null then raise exception 'join the game first'; end if;
  update steals set to_home = v_home
   where id = p_id and to_home is null and kind = 'steal'
     and season = public.current_season()
     and from_home is distinct from v_home;
end;
$$;

grant execute on function public.is_org, public.is_member, public.current_season,
  public.steal_visible, public.season_latest, public.log_steal, public.claim_steal to authenticated;

-- ============ row level security ============
alter table public.organizers enable row level security;
alter table public.config enable row level security;
alter table public.homes enable row level security;
alter table public.joins enable row level security;
alter table public.steals enable row level security;
alter table public.media enable row level security;

do $$ declare r record; begin
  for r in select policyname, tablename from pg_policies
           where schemaname = 'public' and tablename in ('organizers','config','homes','joins','steals','media')
  loop execute format('drop policy %I on public.%I', r.policyname, r.tablename); end loop;
end $$;

-- organizers: no direct access (is_org() reads it)

create policy config_read on public.config for select to authenticated using (public.is_member());
create policy config_write on public.config for all to authenticated using (public.is_org()) with check (public.is_org());

create policy homes_read on public.homes for select to authenticated using (public.is_member());
create policy homes_write on public.homes for all to authenticated using (public.is_org()) with check (public.is_org());

create policy joins_read on public.joins for select to authenticated using (user_id = auth.uid() or public.is_org());
create policy joins_insert on public.joins for insert to authenticated
  with check (user_id = auth.uid() and status = 'pending');
create policy joins_update_own on public.joins for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid() and status = 'pending');
create policy joins_org on public.joins for all to authenticated using (public.is_org()) with check (public.is_org());

create policy steals_read on public.steals for select to authenticated
  using (public.is_member() and public.steal_visible(id, season, from_home, to_home, by_user, at, created_at));
create policy steals_insert on public.steals for insert to authenticated with check (public.is_org());
create policy steals_update on public.steals for update to authenticated
  using (public.is_org() or (by_user = auth.uid() and season = public.current_season()))
  with check (public.is_org() or (by_user = auth.uid() and season = public.current_season()));
create policy steals_delete on public.steals for delete to authenticated
  using (public.is_org() or (by_user = auth.uid() and season = public.current_season()));

create policy media_read on public.media for select to authenticated
  using (public.is_member() and exists (select 1 from public.steals s where s.id = steal_id));
create policy media_insert on public.media for insert to authenticated
  with check (public.is_member() and by_user = auth.uid()
              and exists (select 1 from public.steals s where s.id = steal_id));
create policy media_delete on public.media for delete to authenticated
  using (public.is_org() or by_user = auth.uid());

-- ============ photo & video storage ============
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('media', 'media', false, 52428800,
        array['image/jpeg','image/png','image/webp','image/gif','video/mp4','video/quicktime','video/webm'])
on conflict (id) do update set file_size_limit = excluded.file_size_limit,
                               allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists rg_media_upload on storage.objects;
drop policy if exists rg_media_read on storage.objects;
drop policy if exists rg_media_delete on storage.objects;
create policy rg_media_upload on storage.objects for insert to authenticated
  with check (bucket_id = 'media' and public.is_member());
-- A file is viewable only if its steal is viewable (keeps the newest steal's photos secret too).
create policy rg_media_read on storage.objects for select to authenticated
  using (bucket_id = 'media' and exists (select 1 from public.media m where m.path = name));
create policy rg_media_delete on storage.objects for delete to authenticated
  using (bucket_id = 'media' and (public.is_org() or owner = auth.uid()));

-- ============ live updates ============
do $$ begin
  begin alter publication supabase_realtime add table public.homes; exception when others then null; end;
  begin alter publication supabase_realtime add table public.steals; exception when others then null; end;
  begin alter publication supabase_realtime add table public.media; exception when others then null; end;
  begin alter publication supabase_realtime add table public.joins; exception when others then null; end;
  begin alter publication supabase_realtime add table public.config; exception when others then null; end;
end $$;

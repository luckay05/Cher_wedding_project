-- =====================================================================
-- Cher & Gatha wedding: RSVP database (Supabase / Postgres)
-- Run this whole file once in Supabase: SQL Editor -> New query -> Run.
--
-- Security model
--   * Guests never touch the table directly. The public (anon) key can
--     only call two functions: submit_rsvp() and get_rsvp().
--   * Each guest's browser makes a random secret "edit token". It is the
--     only way to read or change that one reply, so guests can't see
--     anyone else's answers.
--   * Analysis views live in the "analytics" schema, which the public
--     API does not expose. You read them in the Supabase dashboard.
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- 1. The raw replies: one row per RSVP form (a guest + optional plus-one)
-- ---------------------------------------------------------------------
create table if not exists public.rsvps (
  id           bigint generated always as identity primary key,
  edit_token   uuid        not null unique,           -- secret held by the guest's browser
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  edit_count   int         not null default 0,

  name         text not null check (length(btrim(name)) between 1 and 120),
  email        text          check (email is null or (length(email) <= 200 and email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$')),

  attending    boolean not null,                                  -- Bali, 23 Aug 2027
  party        smallint not null default 0 check (party between 0 and 2),
  guest2       text check (guest2 is null or length(guest2) <= 120),
  main1        text,
  main2        text,
  diet         text check (diet is null or length(diet) <= 1000),
  hotel        boolean,                                           -- staying at Swiss-Belresort Pecatu
  shuttle      boolean,                                           -- needs hotel <-> venue shuttle
  song         text check (song is null or length(song) <= 200),
  status       text check (status is null or status in
                 ('Single and ready to mingle','Going with the flow','Off the market','Prefer not to say')),
  hk           boolean not null,                                  -- Hong Kong registry, 5/6 Jun 2027
  message      text check (message is null or length(message) <= 2000),

  -- the menu, kept in one place
  constraint main1_valid check (main1 is null or main1 in
    ('Wagyu Picanha with Bone Marrow','Baked Miso Cod','Grilled Jumbo Prawns','Miso Eggplant')),
  constraint main2_valid check (main2 is null or main2 in
    ('Wagyu Picanha with Bone Marrow','Baked Miso Cod','Grilled Jumbo Prawns','Miso Eggplant')),

  -- the same rules the form enforces, enforced again here
  constraint attending_rules check (
    case when attending then
         party in (1,2) and main1 is not null and hotel is not null and shuttle is not null
     and (party = 1 or (guest2 is not null and length(btrim(guest2)) > 0 and main2 is not null))
     and (party = 2 or (guest2 is null and main2 is null))
    else party = 0 and guest2 is null and main1 is null and main2 is null
     and hotel is null and shuttle is null and song is null and status is null and diet is null
    end)
);

-- Lock the table: RLS on with no policies = no direct access for anon/authenticated
alter table public.rsvps enable row level security;
revoke all on public.rsvps from anon, authenticated;

-- ---------------------------------------------------------------------
-- 2. Functions the website calls
-- ---------------------------------------------------------------------

-- Turn '' / whitespace into null
create or replace function public._clean(t text) returns text
language sql immutable as $$ select nullif(btrim(t), '') $$;

create or replace function public._yesno(t text) returns boolean
language sql immutable as $$
  select case lower(btrim(coalesce(t,''))) when 'yes' then true when 'no' then false else null end
$$;

-- Insert or update a reply. p is the JSON the form already builds:
-- {name,email,attending,party,guest2,main1,main2,diet,hotel,shuttle,song,status,hk,message,website}
create or replace function public.submit_rsvp(p jsonb, p_token uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_att   boolean := public._yesno(p->>'attending');
  v_party smallint;
  v_two   boolean;
  r       public.rsvps;
begin
  if p_token is null then raise exception 'missing token' using errcode = '22023'; end if;
  -- honeypot: a hidden field real people never fill in
  if public._clean(p->>'website') is not null then raise exception 'rejected' using errcode = '22023'; end if;
  if v_att is null then raise exception 'attending must be yes or no' using errcode = '22023'; end if;
  -- a little flood protection: at most 200 new replies per hour across the site
  if not exists (select 1 from public.rsvps where edit_token = p_token)
     and (select count(*) from public.rsvps where created_at > now() - interval '1 hour') >= 200 then
    raise exception 'too many replies, try later' using errcode = '53400';
  end if;

  v_party := case when v_att then coalesce(nullif(p->>'party','')::smallint, 0) else 0 end;
  v_two   := v_att and v_party = 2;

  insert into public.rsvps as t
    (edit_token, name, email, attending, party, guest2, main1, main2, diet,
     hotel, shuttle, song, status, hk, message)
  values (
    p_token,
    public._clean(p->>'name'),
    lower(public._clean(p->>'email')),
    v_att,
    v_party,
    case when v_two then public._clean(p->>'guest2') end,
    case when v_att then public._clean(p->>'main1') end,
    case when v_two then public._clean(p->>'main2') end,
    case when v_att then public._clean(p->>'diet') end,
    case when v_att then public._yesno(p->>'hotel') end,
    case when v_att then public._yesno(p->>'shuttle') end,
    case when v_att then public._clean(p->>'song') end,
    case when v_att then public._clean(p->>'status') end,
    public._yesno(p->>'hk'),
    public._clean(p->>'message'))
  on conflict (edit_token) do update set
    name = excluded.name, email = excluded.email, attending = excluded.attending,
    party = excluded.party, guest2 = excluded.guest2, main1 = excluded.main1,
    main2 = excluded.main2, diet = excluded.diet, hotel = excluded.hotel,
    shuttle = excluded.shuttle, song = excluded.song, status = excluded.status,
    hk = excluded.hk, message = excluded.message,
    updated_at = now(), edit_count = t.edit_count + 1
  returning * into r;

  return jsonb_build_object('ok', true, 'updated', r.edit_count > 0);
end $$;

-- Read back your own reply (to pre-fill "Change my reply")
create or replace function public.get_rsvp(p_token uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'name', name, 'email', coalesce(email,''),
    'attending', case when attending then 'yes' else 'no' end,
    'party', party, 'guest2', coalesce(guest2,''),
    'main1', coalesce(main1,''), 'main2', coalesce(main2,''), 'diet', coalesce(diet,''),
    'hotel', case hotel when true then 'yes' when false then 'no' else '' end,
    'shuttle', case shuttle when true then 'yes' when false then 'no' else '' end,
    'song', coalesce(song,''), 'status', coalesce(status,''),
    'hk', case when hk then 'yes' else 'no' end,
    'message', coalesce(message,''))
  from public.rsvps where edit_token = p_token
$$;

-- Tiny query for the keep-alive job (touches the database, returns no guest data)
create or replace function public.ping()
returns boolean language sql stable security definer set search_path = public, pg_temp
as $$ select exists (select 1 from public.rsvps) or true $$;

-- Only these are callable with the public key
revoke all on function public.submit_rsvp(jsonb, uuid) from public;
revoke all on function public.get_rsvp(uuid)           from public;
revoke all on function public.ping()                   from public;
revoke all on function public._clean(text)             from public, anon, authenticated;
revoke all on function public._yesno(text)             from public, anon, authenticated;
grant execute on function public.submit_rsvp(jsonb, uuid) to anon, authenticated;
grant execute on function public.get_rsvp(uuid)           to anon, authenticated;
grant execute on function public.ping()                   to anon, authenticated;

-- =====================================================================
-- Cher & Gatha wedding: analysis views
-- Run after 01_schema.sql. These live in the "analytics" schema, which
-- the public API can't see. Open them in Supabase: Table Editor ->
-- schema dropdown -> analytics. Each view has an "Export to CSV" option.
-- =====================================================================

create schema if not exists analytics;
revoke all on schema analytics from public, anon, authenticated;

-- One row per PERSON coming to Bali (the RSVPer and their plus-one split out).
-- Most counting is easiest from here.
create or replace view analytics.guests as
  select r.id as rsvp_id, 1 as seat, r.name as guest_name, r.main1 as main,
         r.hotel, r.shuttle, r.diet, false as is_plus_one, r.name as invited_by
  from public.rsvps r where r.attending
  union all
  select r.id, 2, r.guest2, r.main2, r.hotel, r.shuttle, r.diet, true, r.name
  from public.rsvps r where r.attending and r.party = 2;

-- The headline numbers
create or replace view analytics.summary as
  select
    (select count(*) from public.rsvps)                                as replies,
    (select count(*) from public.rsvps where attending)                as replies_attending,
    (select count(*) from public.rsvps where not attending)            as replies_declining,
    (select count(*) from analytics.guests)                            as bali_headcount,
    (select count(*) from analytics.guests where is_plus_one)          as plus_ones,
    (select count(*) from analytics.guests where hotel)                as staying_at_resort,
    (select count(*) from analytics.guests where shuttle)              as shuttle_seats,
    (select count(*) from public.rsvps where hk)                       as hk_replies_yes,
    (select count(*) from public.rsvps where diet is not null)         as replies_with_dietary_notes,
    (select max(updated_at) from public.rsvps)                         as last_reply_at;

-- Main course counts for the caterer
create or replace view analytics.mains as
  select m.main, count(g.main) as plates
  from (values ('Wagyu Picanha with Bone Marrow',1),('Baked Miso Cod',2),
               ('Grilled Jumbo Prawns',3),('Miso Eggplant',4)) as m(main, ord)
  left join analytics.guests g on g.main = m.main
  group by m.main, m.ord
  order by m.ord;

-- Everyone with a dietary note, and what they ordered
create or replace view analytics.dietary as
  select r.name, r.guest2 as plus_one, r.main1, r.main2, r.diet
  from public.rsvps r
  where r.attending and r.diet is not null
  order by r.name;

-- Shuttle list
create or replace view analytics.shuttle as
  select guest_name, invited_by, hotel as staying_at_resort
  from analytics.guests where shuttle
  order by invited_by, seat;

-- Hong Kong registry list
create or replace view analytics.hong_kong as
  select name, email, attending as also_coming_to_bali
  from public.rsvps where hk order by name;

-- Replies per day (to see how the response rate builds up)
create or replace view analytics.replies_by_day as
  select (created_at at time zone 'Australia/Sydney')::date as day,
         count(*) as new_replies,
         sum(count(*)) over (order by (created_at at time zone 'Australia/Sydney')::date) as running_total
  from public.rsvps
  group by 1 order by 1;

-- Dance floor requests
create or replace view analytics.songs as
  select min(song) as song, string_agg(name, ', ' order by name) as requested_by, count(*) as votes
  from public.rsvps where song is not null
  group by lower(btrim(song))
  order by votes desc, 1;

-- Relationship status mix (for the seating plan, of course)
create or replace view analytics.status_mix as
  select coalesce(status, '(not answered)') as status, count(*) as replies
  from public.rsvps where attending
  group by 1 order by replies desc;

-- Wishes & messages, newest first
create or replace view analytics.messages as
  select name, message, created_at
  from public.rsvps where message is not null
  order by created_at desc;

-- Full export, one row per reply, in a spreadsheet-friendly shape
create or replace view analytics.all_replies as
  select id, name, email,
         case when attending then 'yes' else 'no' end as bali,
         party, guest2, main1, main2, diet,
         case hotel when true then 'yes' when false then 'no' end as hotel,
         case shuttle when true then 'yes' when false then 'no' end as shuttle,
         song, status,
         case when hk then 'yes' else 'no' end as hong_kong,
         message, created_at, updated_at, edit_count
  from public.rsvps order by name;

revoke all on all tables in schema analytics from public, anon, authenticated;

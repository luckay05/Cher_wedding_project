# RSVP database setup (Supabase + GitHub Pages)

How it fits together:

```
Guest's browser (GitHub Pages: index.html)
   │  POST /rest/v1/rpc/submit_rsvp   (publishable key + secret edit token)
   ▼
Supabase API ──► submit_rsvp() / get_rsvp()  ──► table public.rsvps   (locked: no direct access)
                                                      │
You & Cher (Supabase dashboard) ◄── analytics.* views ┘   → Export CSV / SQL / pandas
```

Guests can only *call two functions*. They can never list or read the table, so nobody can see anyone else's reply.

## 1. Create the project (5 min)

1. Sign up at supabase.com and create a **New project**.
   - Name: `cher-gatha-wedding`
   - Region: **Southeast Asia (Singapore)**, closest to both Australia and Bali.
   - Save the database password somewhere safe (you won't need it for the site).
2. Wait for it to finish provisioning.

## 2. Build the database

1. Open **SQL Editor → New query**.
2. Paste all of `supabase/01_schema.sql` and click **Run**.
3. Do the same with `supabase/02_analytics.sql`.

Both files are safe to run again if you change something later.

## 3. Connect the website

1. Go to **Project Settings → API Keys** and copy the **Project URL** and the **publishable** key (starts `sb_publishable_`; older projects call it the `anon` key).
   - Never put the **secret** / `service_role` key in the website.
2. In `index.html`, search for `SUPABASE_URL` and paste both values in:
   ```js
   const SUPABASE_URL = 'https://abcdefghijkl.supabase.co';
   const SUPABASE_KEY = 'sb_publishable_...';
   ```
3. Commit and push `index.html` to your GitHub Pages repo.

## 4. Keep it awake (free plan)

Free projects pause after about a week without database activity. The wedding is ~10 months away, so:

1. Copy `.github/workflows/supabase-keepalive.yml` into the same repo.
2. In GitHub go to **Settings → Secrets and variables → Actions**, and add two secrets: `SUPABASE_URL` and `SUPABASE_KEY`.
3. Go to **Actions → Supabase keep-alive → Run workflow** once to check it goes green.

GitHub can switch off scheduled workflows in repos that have had no commits for a couple of months. If you get an email about that, click to re-enable it.

## 5. Test before sending invites

1. Open the live site, fill in the RSVP, and submit.
2. In Supabase, open **Table Editor → schema: public → rsvps**. Your row should be there.
3. Reload the site. It should show your reply with "Change my reply".
4. Delete the test row before invites go out (Table Editor → select row → Delete).

## 6. Analysing the replies

Open **Table Editor**, switch the schema dropdown to **analytics**, and click any view. Each view has **Export → CSV** for Cher or the caterer.

| View | What it answers |
|---|---|
| `summary` | Headcount, plus-ones, resort guests, shuttle seats, HK yes count |
| `guests` | One row per person (plus-ones split out). Best for any counting |
| `mains` | Plates of each main course, for the caterer |
| `dietary` | Everyone with a dietary note and what they ordered |
| `shuttle` | Who needs the shuttle |
| `hong_kong` | Who's coming to the HK registry |
| `replies_by_day` | How replies build up over time, with a running total |
| `songs` | Song requests, merged and ranked |
| `status_mix` | Relationship status counts |
| `messages` | Wishes, newest first |
| `all_replies` | Everything, spreadsheet-friendly |

For your own questions, use **SQL Editor**, e.g.:

```sql
-- Resort guests who did NOT ask for the shuttle (check they have transport)
select guest_name, invited_by from analytics.guests where hotel and not shuttle;

-- Who has edited their reply more than twice
select name, edit_count, updated_at from public.rsvps where edit_count > 2;
```

## How editing works

- When a guest first submits, their browser makes a random secret token and saves it.
- Coming back on the same browser shows their reply.
- The thank-you message also gives them a personal link (`?rsvp=<token>`) so they can edit from another device.
- If someone loses both, they'll just submit again. You'll see a duplicate name in `all_replies` and can delete the older row.

## Privacy notes

- Emails and dietary notes are personal data. Share CSV exports only with people who need them, and don't post screenshots of the table.
- After the wedding, export what you want to keep, then delete the project (Settings → General → Delete project).

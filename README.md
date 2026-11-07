# Reindeer Games

Emerald Bay's neighborhood Rudolph-stealing game. Families steal an inflatable Rudolph from each other all December and log each capture here with photos and videos.

- **Site:** hosted on GitHub Pages from this repo (`index.html`).
- **Data:** families, steals, photos and sign-ins live in a [Supabase](https://supabase.com) project. Nothing about the game is stored in this repo.

## Files

| File | What it is |
| --- | --- |
| `index.html` | The whole site |
| `config.js` | Your Supabase project URL and public (anon) key |
| `assets/` | Emerald Bay map images (light and dark) |
| `supabase/setup.sql` | Creates the database, security rules and photo storage |

## One-time setup

### 1. Create the Supabase project
1. Sign up at supabase.com and click **New project**. Any name works (for example `reindeer-games`). Pick the region closest to California (West US).
2. When it finishes, open **SQL Editor → New query**, paste all of `supabase/setup.sql`, and click **Run**.
3. Make yourself the organizer. In a new query, run (with your email):
   ```sql
   insert into public.organizers (email) values ('you@example.com');
   ```

### 2. Connect the site
1. In Supabase, open **Project Settings → API** and copy the **Project URL** and the **anon public** key.
2. Paste them into `config.js`. The anon key is designed to be public: the database rules decide who can see what.

### 3. Sign-in emails
1. In Supabase, open **Authentication → URL Configuration**:
   - **Site URL:** `https://westwoodeleven.github.io/Reindeer-Games/`
   - **Redirect URLs:** add the same address.
2. Recommended: open **Authentication → Emails → Magic Link** and add this line to the message, so people can type a code instead of tapping the link:
   `Or enter this code: {{ .Token }}`
3. Before inviting the neighborhood, set up custom email sending (**Authentication → Emails → SMTP Settings**). Supabase's built-in sender only allows a few emails per hour and is meant for testing. A free [Resend](https://resend.com) account works well.

### 4. Turn on GitHub Pages
In this repo: **Settings → Pages → Build and deployment → Deploy from a branch → `main` / root**.

## How access works
- Anyone can open the site, but they only see a sign-in screen.
- After signing in by email, a family requests to join. The organizer approves them under **Organizer → Join requests**.
- The organizer is whoever is listed in the `organizers` table.
- The newest steal is hidden by the database itself from everyone except the organizer and the two families involved, until Rudolph is stolen again. Its photos and videos stay hidden too.

## Limits (Supabase free plan)
- Photos and videos: up to 50 MB per file, 1 GB total storage.
- Free projects pause after a week with no visitors. Opening the Supabase dashboard wakes it up. During the game, daily use keeps it awake.

# V PULSE — Supabase setup

The database schema is in [schema.sql](./schema.sql). It creates:

- user profiles linked to Supabase Auth;
- posts, likes and comments;
- friend requests;
- private one-to-one messages;
- a media storage bucket;
- Row Level Security (RLS) policies and Realtime publication for feed/comments/messages.

## Create the hosted database

1. Open https://supabase.com/dashboard and sign in.
2. Choose **New project**, name it `V PULSE`, select a region close to most users, set a strong database password and create the project.
3. Wait for provisioning to finish.
4. Open **SQL Editor** → **New query**.
5. Open this repository's `supabase/schema.sql`, copy the complete contents into the query editor and press **Run**.
6. In **Project Settings → API** (or **Data API** in the current dashboard), copy the Project URL and the **publishable** key (or legacy `anon` key).
7. Never put the `service_role` / secret key in the website or commit it to GitHub.

## Website connection

The current GitHub Pages site is a static demo and does not yet use a Supabase project. Once the project URL and publishable key are available, wire the browser client to Supabase Auth and the tables above. Keep the database protected by the included RLS policies. Do not disable RLS and do not expose the database password or service-role key.

## Important

The SQL file defines the database schema and security policies; committing it to GitHub does not provision a live Supabase project. The project must be created in Supabase and the SQL must be run once in its SQL Editor.

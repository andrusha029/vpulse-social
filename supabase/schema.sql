-- V PULSE database schema for Supabase (PostgreSQL)
-- Run this file in Supabase Dashboard -> SQL Editor -> New query.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text unique,
  display_name text not null default 'Новый пользователь',
  avatar_url text,
  bio text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint username_format check (username is null or username ~ '^[a-zA-Z0-9_]{3,24}$')
);

create table if not exists public.posts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references public.profiles(id) on delete cascade,
  body text not null default '',
  media_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint post_has_content check (length(trim(body)) > 0 or media_url is not null),
  constraint post_body_length check (char_length(body) <= 10000)
);

create table if not exists public.likes (
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);

create table if not exists public.comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  author_id uuid not null references public.profiles(id) on delete cascade,
  body text not null check (char_length(trim(body)) between 1 and 3000),
  created_at timestamptz not null default now()
);

create table if not exists public.friendships (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references public.profiles(id) on delete cascade,
  addressee_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','accepted','declined','blocked')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint friendship_not_self check (requester_id <> addressee_id),
  constraint friendship_pair_unique unique (requester_id, addressee_id)
);

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references public.profiles(id) on delete cascade,
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  body text not null check (char_length(trim(body)) between 1 and 10000),
  created_at timestamptz not null default now(),
  read_at timestamptz,
  constraint message_not_self check (sender_id <> recipient_id)
);

create index if not exists posts_created_at_idx on public.posts (created_at desc);
create index if not exists posts_author_created_idx on public.posts (author_id, created_at desc);
create index if not exists comments_post_created_idx on public.comments (post_id, created_at);
create index if not exists messages_conversation_idx on public.messages (sender_id, recipient_id, created_at desc);
create index if not exists friendships_addressee_status_idx on public.friendships (addressee_id, status);

-- Automatically create a profile when a user registers.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, username, display_name, avatar_url)
  values (
    new.id,
    nullif(new.raw_user_meta_data ->> 'username', ''),
    coalesce(nullif(new.raw_user_meta_data ->> 'display_name', ''), split_part(coalesce(new.email, 'Пользователь'), '@', 1)),
    nullif(new.raw_user_meta_data ->> 'avatar_url', '')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- Keep updated_at current on profile/post/friendship edits.
create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at before update on public.profiles
for each row execute procedure public.set_updated_at();

drop trigger if exists posts_set_updated_at on public.posts;
create trigger posts_set_updated_at before update on public.posts
for each row execute procedure public.set_updated_at();

drop trigger if exists friendships_set_updated_at on public.friendships;
create trigger friendships_set_updated_at before update on public.friendships
for each row execute procedure public.set_updated_at();

alter table public.profiles enable row level security;
alter table public.posts enable row level security;
alter table public.likes enable row level security;
alter table public.comments enable row level security;
alter table public.friendships enable row level security;
alter table public.messages enable row level security;

-- Profiles: visible to signed-in users; users may edit only their own profile.
drop policy if exists "Profiles are viewable by authenticated users" on public.profiles;
create policy "Profiles are viewable by authenticated users"
on public.profiles for select to authenticated using (true);
drop policy if exists "Users can insert their own profile" on public.profiles;
create policy "Users can insert their own profile"
on public.profiles for insert to authenticated with check (auth.uid() = id);
drop policy if exists "Users can update their own profile" on public.profiles;
create policy "Users can update their own profile"
on public.profiles for update to authenticated using (auth.uid() = id) with check (auth.uid() = id);

-- Posts: signed-in users can read; authors create/update/delete their own posts.
drop policy if exists "Posts are viewable by authenticated users" on public.posts;
create policy "Posts are viewable by authenticated users"
on public.posts for select to authenticated using (true);
drop policy if exists "Users can create their own posts" on public.posts;
create policy "Users can create their own posts"
on public.posts for insert to authenticated with check (auth.uid() = author_id);
drop policy if exists "Authors can update their own posts" on public.posts;
create policy "Authors can update their own posts"
on public.posts for update to authenticated using (auth.uid() = author_id) with check (auth.uid() = author_id);
drop policy if exists "Authors can delete their own posts" on public.posts;
create policy "Authors can delete their own posts"
on public.posts for delete to authenticated using (auth.uid() = author_id);

-- Likes: visible to signed-in users; a user controls only their own likes.
drop policy if exists "Likes are viewable by authenticated users" on public.likes;
create policy "Likes are viewable by authenticated users"
on public.likes for select to authenticated using (true);
drop policy if exists "Users can like as themselves" on public.likes;
create policy "Users can like as themselves"
on public.likes for insert to authenticated with check (auth.uid() = user_id);
drop policy if exists "Users can remove their own likes" on public.likes;
create policy "Users can remove their own likes"
on public.likes for delete to authenticated using (auth.uid() = user_id);

-- Comments: visible to signed-in users; users may create/edit/delete their own comments.
drop policy if exists "Comments are viewable by authenticated users" on public.comments;
create policy "Comments are viewable by authenticated users"
on public.comments for select to authenticated using (true);
drop policy if exists "Users can create their own comments" on public.comments;
create policy "Users can create their own comments"
on public.comments for insert to authenticated with check (auth.uid() = author_id);
drop policy if exists "Authors can update their own comments" on public.comments;
create policy "Authors can update their own comments"
on public.comments for update to authenticated using (auth.uid() = author_id) with check (auth.uid() = author_id);
drop policy if exists "Authors can delete their own comments" on public.comments;
create policy "Authors can delete their own comments"
on public.comments for delete to authenticated using (auth.uid() = author_id);

-- Friendship participants can see and update requests involving them.
drop policy if exists "Users can view their friendship requests" on public.friendships;
create policy "Users can view their friendship requests"
on public.friendships for select to authenticated
using (auth.uid() = requester_id or auth.uid() = addressee_id);
drop policy if exists "Users can send friendship requests" on public.friendships;
create policy "Users can send friendship requests"
on public.friendships for insert to authenticated with check (auth.uid() = requester_id);
drop policy if exists "Recipients can respond to friendship requests" on public.friendships;
create policy "Recipients can respond to friendship requests"
on public.friendships for update to authenticated
using (auth.uid() = addressee_id or auth.uid() = requester_id)
with check (auth.uid() = addressee_id or auth.uid() = requester_id);
drop policy if exists "Participants can delete friendship requests" on public.friendships;
create policy "Participants can delete friendship requests"
on public.friendships for delete to authenticated
using (auth.uid() = requester_id or auth.uid() = addressee_id);

-- Private messages: only sender and recipient can read; sender creates, recipient marks read.
drop policy if exists "Participants can read their messages" on public.messages;
create policy "Participants can read their messages"
on public.messages for select to authenticated
using (auth.uid() = sender_id or auth.uid() = recipient_id);
drop policy if exists "Users can send messages as themselves" on public.messages;
create policy "Users can send messages as themselves"
on public.messages for insert to authenticated with check (auth.uid() = sender_id);
drop policy if exists "Recipients can mark messages as read" on public.messages;
create policy "Recipients can mark messages as read"
on public.messages for update to authenticated
using (auth.uid() = recipient_id)
with check (auth.uid() = recipient_id);

-- Public media bucket; uploads are restricted to a folder named with the user's auth UID.
insert into storage.buckets (id, name, public)
values ('vpulse-media', 'vpulse-media', true)
on conflict (id) do nothing;

drop policy if exists "V PULSE media is publicly readable" on storage.objects;
create policy "V PULSE media is publicly readable"
on storage.objects for select
using (bucket_id = 'vpulse-media');

drop policy if exists "Users upload media to their own folder" on storage.objects;
create policy "Users upload media to their own folder"
on storage.objects for insert to authenticated
with check (bucket_id = 'vpulse-media' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "Users update media in their own folder" on storage.objects;
create policy "Users update media in their own folder"
on storage.objects for update to authenticated
using (bucket_id = 'vpulse-media' and owner_id = auth.uid()::text)
with check (bucket_id = 'vpulse-media' and owner_id = auth.uid()::text);

drop policy if exists "Users delete media in their own folder" on storage.objects;
create policy "Users delete media in their own folder"
on storage.objects for delete to authenticated
using (bucket_id = 'vpulse-media' and owner_id = auth.uid()::text);

-- Realtime publication for live feed and chats (safe if already included).
do $$
begin
  alter publication supabase_realtime add table public.posts;
exception when duplicate_object then null;
end $$;
do $$
begin
  alter publication supabase_realtime add table public.comments;
exception when duplicate_object then null;
end $$;
do $$
begin
  alter publication supabase_realtime add table public.messages;
exception when duplicate_object then null;
end $$;

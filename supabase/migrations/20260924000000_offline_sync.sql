-- Offline-first sync support
-- Run this once in the Supabase dashboard (SQL Editor) BEFORE shipping the app version
-- that uses schemaVersion 2 / incremental sync.
--
-- Every synced table gets two timestamps:
--   updated_at         when a device last edited the row. Sent by the app, used for
--                      "last write wins" when two devices edit the same row.
--   server_updated_at  when the server last received the row. Set by the trigger below,
--                      never by the app. Devices pull "everything changed since X" using
--                      this, so edits uploaded late by an offline device are still seen.

-- 1. Trigger function shared by every table
create or replace function public.set_server_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.server_updated_at = now();
  return new;
end;
$$;

-- 2. Tables that didn't exist on the server yet (they were never synced before)
create table if not exists public.savings_goals (
  id uuid primary key,
  name text not null,
  target_amount double precision not null,
  current_saved_amount double precision not null,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  is_active boolean not null default true,
  is_deleted boolean not null default false
);

create table if not exists public.investments (
  id uuid primary key,
  name text not null,
  amount double precision not null,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  is_active boolean not null default true,
  is_deleted boolean not null default false
);

-- Only let people see and change their own rows. Compare these with the policies on
-- categories/transactions/templates, they should match
alter table public.savings_goals enable row level security;
alter table public.investments enable row level security;

drop policy if exists "Users manage their own savings goals" on public.savings_goals;
create policy "Users manage their own savings goals" on public.savings_goals
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "Users manage their own investments" on public.investments;
create policy "Users manage their own investments" on public.investments
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- 3. Timestamps, trigger and index on every synced table
do $$
declare
  t text;
begin
  foreach t in array array['categories', 'templates', 'transactions', 'savings_goals', 'investments']
  loop
    execute format('alter table public.%I add column if not exists updated_at timestamptz not null default now()', t);
    execute format('alter table public.%I add column if not exists server_updated_at timestamptz not null default now()', t);

    execute format('drop trigger if exists set_server_updated_at on public.%I', t);
    execute format(
      'create trigger set_server_updated_at before insert or update on public.%I
       for each row execute function public.set_server_updated_at()', t);

    -- The app asks "rows for this user changed since X", this makes that fast
    execute format(
      'create index if not exists %I on public.%I (user_id, server_updated_at)',
      t || '_user_id_server_updated_at_idx', t);
  end loop;
end;
$$;

-- 4. Sanity check: the app used to upload categories without "type". Rows where it's
-- missing can't be pulled, so fix them (0 = income, 1 = expense) before syncing:
--   select id, name from public.categories where type is null;
--   update public.categories set type = 1 where type is null;

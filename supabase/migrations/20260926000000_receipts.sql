-- Receipts: the table and the private bucket for their photos
-- Run this once in the Supabase dashboard (SQL Editor), after 20260924000000_offline_sync.sql.
-- Until it's run, the app still works, but syncing receipts fails (the sync icon shows it).

-- 1. The receipts table, with the same sync columns as every other table
create table if not exists public.receipts (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  merchant text,
  total double precision,
  date timestamptz,
  -- No foreign keys on these two, the app syncs tables one at a time and checks them itself
  category_id uuid,
  transaction_id uuid,
  scan_status smallint not null default 0,
  image_uploaded boolean not null default false,
  is_favorite boolean not null default false,
  board_x double precision,
  board_y double precision,
  board_z integer not null default 0,
  created_at timestamptz not null default now(),
  is_deleted boolean not null default false,
  updated_at timestamptz not null default now(),
  server_updated_at timestamptz not null default now()
);

alter table public.receipts enable row level security;

drop policy if exists "Users manage their own receipts" on public.receipts;
create policy "Users manage their own receipts" on public.receipts
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Same trigger and index as the other synced tables (the function comes from the
-- offline_sync migration)
drop trigger if exists set_server_updated_at on public.receipts;
create trigger set_server_updated_at before insert or update on public.receipts
  for each row execute function public.set_server_updated_at();

create index if not exists receipts_user_id_server_updated_at_idx
  on public.receipts (user_id, server_updated_at);

-- 2. The photos. A private bucket: nothing in it is public, every read needs a signed-in user
insert into storage.buckets (id, name, public)
values ('receipts', 'receipts', false)
on conflict (id) do nothing;

-- Each photo is stored as "<user id>/<receipt id>.jpg". These policies only let a user
-- touch files inside the folder named after their own id
drop policy if exists "Users read their own receipt photos" on storage.objects;
create policy "Users read their own receipt photos" on storage.objects
  for select using (bucket_id = 'receipts' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "Users upload their own receipt photos" on storage.objects;
create policy "Users upload their own receipt photos" on storage.objects
  for insert with check (bucket_id = 'receipts' and (storage.foldername(name))[1] = auth.uid()::text);

-- Needed because the app uploads with upsert (re-uploading overwrites the same file)
drop policy if exists "Users replace their own receipt photos" on storage.objects;
create policy "Users replace their own receipt photos" on storage.objects
  for update using (bucket_id = 'receipts' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "Users delete their own receipt photos" on storage.objects;
create policy "Users delete their own receipt photos" on storage.objects
  for delete using (bucket_id = 'receipts' and (storage.foldername(name))[1] = auth.uid()::text);

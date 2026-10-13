-- Where receipts are from
-- Run this once in the Supabase SQL Editor, after 20260928000000_receipt_crop.sql.
-- Until it's run, syncing receipts fails (the sync icon shows it).

alter table public.receipts add column if not exists city text;
alter table public.receipts add column if not exists state text;
alter table public.receipts add column if not exists country text;

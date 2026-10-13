-- Receipt rotation and bill splitting
-- Run this once in the Supabase SQL Editor, after 20260926000000_receipts.sql.
-- Until it's run, syncing receipts fails (the sync icon shows it).

-- Quarter turns clockwise (0-3) to show the photo upright. The photo file never changes
alter table public.receipts add column if not exists image_quarter_turns smallint not null default 0;

-- Splitting with friends: how many people for an equal split (you included), or your own
-- amount for a custom split. Both null means you paid for all of it
alter table public.receipts add column if not exists split_people smallint;
alter table public.receipts add column if not exists split_amount double precision;

-- Receipt suburbs, and photo coordinates waiting to be named
-- Run this once in the Supabase SQL Editor, after 20260929000000_receipt_location.sql.
-- Until it's run, syncing receipts fails (the sync icon shows it).

-- The part of the city, e.g. Etobicoke in Toronto
alter table public.receipts add column if not exists suburb text;

-- Where a photo was taken (from its EXIF data), only while it waits for the phone to turn it
-- into a place name. The phone clears these as soon as it has named the place
alter table public.receipts add column if not exists pending_latitude double precision;
alter table public.receipts add column if not exists pending_longitude double precision;

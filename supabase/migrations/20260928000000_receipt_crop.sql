-- Cutting receipts out of their photos
-- Run this once in the Supabase SQL Editor, after 20260927000000_receipt_rotation_split.sql.
-- Until it's run, syncing receipts fails (the sync icon shows it).

-- The receipt's four corners in the photo, as fractions: "x1,y1,x2,y2,x3,y3,x4,y4"
-- (top-left, top-right, bottom-right, bottom-left). The photo itself never changes, each
-- device crops its own copy. Null shows the whole photo
alter table public.receipts add column if not exists crop_corners text;

-- Run this in the Supabase SQL editor to add certified_at tracking
ALTER TABLE public.member_skills
  ADD COLUMN IF NOT EXISTS certified_at timestamptz;

-- Run this SQL in your Supabase Dashboard SQL Editor to add the signature column
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS signature_url TEXT;

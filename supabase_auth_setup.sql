s-- ============================================
-- TEAM AUTHENTICATION - SUPABASE SETUP
-- ============================================
-- Run this SQL in your Supabase SQL Editor (Dashboard → SQL Editor → New Query)
--
-- This creates a secure team_auth table with bcrypt-hashed passwords
-- and an RPC function for server-side password verification.
-- No plaintext passwords are stored or exposed to the frontend.
-- ============================================

-- 1. ENABLE pgcrypto EXTENSION (for password hashing)
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

-- 2. CREATE team_auth TABLE
CREATE TABLE IF NOT EXISTS public.team_auth (
  id SERIAL PRIMARY KEY,
  team_name TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  is_admin BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. ENABLE ROW LEVEL SECURITY (block direct table access)
ALTER TABLE public.team_auth ENABLE ROW LEVEL SECURITY;
-- No SELECT/INSERT/UPDATE/DELETE policies = nobody can read the table directly via REST API.
-- The RPC function uses SECURITY DEFINER to bypass RLS.

-- 4. CREATE SERVER-SIDE LOGIN VERIFICATION FUNCTION
--    This function runs with the table owner's privileges (SECURITY DEFINER),
--    so the anon role can call it but cannot read the table directly.
CREATE OR REPLACE FUNCTION public.verify_team_login(p_team TEXT, p_password TEXT)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.team_auth
    WHERE team_name = p_team
      AND password_hash = extensions.crypt(p_password, password_hash)
  );
$$;

-- 5. GRANT EXECUTE PERMISSION TO ANON ROLE
GRANT EXECUTE ON FUNCTION public.verify_team_login(TEXT, TEXT) TO anon;

-- 6. SEED TEAM CREDENTIALS (bcrypt-hashed)
--    ⚠️ IMPORTANT: Change these passwords after initial setup!
--    To update a password later, run:
--      UPDATE public.team_auth SET password_hash = extensions.crypt('NEW_PASSWORD', extensions.gen_salt('bf')) WHERE team_name = 'TEAM_NAME';
INSERT INTO public.team_auth (team_name, password_hash, is_admin) VALUES
  ('Ibri',       extensions.crypt('ib11',      extensions.gen_salt('bf')), false),
  ('Wadi Alain', extensions.crypt('wa22',      extensions.gen_salt('bf')), false),
  ('Araqi',      extensions.crypt('ar33',      extensions.gen_salt('bf')), false),
  ('Hijermat',   extensions.crypt('hj44',      extensions.gen_salt('bf')), false),
  ('Dank',       extensions.crypt('dk55',      extensions.gen_salt('bf')), false),
  ('Yanqul',     extensions.crypt('yq66',      extensions.gen_salt('bf')), false),
  ('__admin__',  extensions.crypt('admin2025', extensions.gen_salt('bf')), true)
ON CONFLICT (team_name) DO NOTHING;

-- ============================================
-- HELPER: CHANGE A TEAM PASSWORD
-- ============================================
-- UPDATE public.team_auth
-- SET password_hash = extensions.crypt('NEW_PASSWORD_HERE', extensions.gen_salt('bf'))
-- WHERE team_name = 'TEAM_NAME_HERE';
--
-- Example - change admin password:
-- UPDATE public.team_auth
-- SET password_hash = extensions.crypt('myNewSecurePassword', extensions.gen_salt('bf'))
-- WHERE team_name = '__admin__';
-- ============================================

-- ============================================
-- PASSWORD RESET REQUESTS TABLE
-- ============================================

-- 7. CREATE password_reset_requests TABLE
CREATE TABLE IF NOT EXISTS public.password_reset_requests (
  id SERIAL PRIMARY KEY,
  team_name TEXT NOT NULL,
  requester_name TEXT,
  reason TEXT,
  status TEXT NOT NULL DEFAULT 'pending',
  reviewed_by TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  reviewed_at TIMESTAMPTZ
);

ALTER TABLE public.password_reset_requests ENABLE ROW LEVEL SECURITY;

GRANT SELECT, INSERT ON public.password_reset_requests TO anon;
GRANT USAGE, SELECT ON SEQUENCE password_reset_requests_id_seq TO anon;

-- 8. RPC: Submit a password reset request (called by team users)
CREATE OR REPLACE FUNCTION public.request_password_reset(p_team TEXT, p_requester TEXT DEFAULT NULL, p_reason TEXT DEFAULT NULL)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Only allow for existing non-admin teams
  IF NOT EXISTS (SELECT 1 FROM public.team_auth WHERE team_name = p_team AND is_admin = false) THEN
    RETURN;  -- Silent: don't reveal if team exists
  END IF;
  -- Prevent duplicate pending requests (1 per hour per team)
  IF EXISTS (
    SELECT 1 FROM public.password_reset_requests
    WHERE team_name = p_team AND status = 'pending'
      AND created_at > NOW() - INTERVAL '1 hour'
  ) THEN
    RETURN;
  END IF;
  INSERT INTO public.password_reset_requests (team_name, requester_name, reason)
  VALUES (p_team, p_requester, p_reason);
END;
$$;

GRANT EXECUTE ON FUNCTION public.request_password_reset(TEXT, TEXT, TEXT) TO anon;

-- 9. RPC: Admin resets a team's password (admin password required for auth)
CREATE OR REPLACE FUNCTION public.admin_reset_team_password(p_admin_pass TEXT, p_team TEXT, p_new_password TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  -- Verify caller is admin
  IF NOT EXISTS (
    SELECT 1 FROM public.team_auth
    WHERE team_name = '__admin__'
      AND password_hash = extensions.crypt(p_admin_pass, password_hash)
  ) THEN
    RETURN false;
  END IF;
  -- Update the team's password
  UPDATE public.team_auth
  SET password_hash = extensions.crypt(p_new_password, extensions.gen_salt('bf'))
  WHERE team_name = p_team AND is_admin = false;
  IF NOT FOUND THEN RETURN false; END IF;
  -- Mark pending requests as approved
  UPDATE public.password_reset_requests
  SET status = 'approved', reviewed_by = '__admin__', reviewed_at = NOW()
  WHERE team_name = p_team AND status = 'pending';
  RETURN true;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_reset_team_password(TEXT, TEXT, TEXT) TO anon;

-- 10. RPC: Admin views pending reset requests (admin password required)
CREATE OR REPLACE FUNCTION public.get_pending_reset_requests(p_admin_pass TEXT)
RETURNS TABLE(id INT, team_name TEXT, requester_name TEXT, reason TEXT, created_at TIMESTAMPTZ)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  -- Verify caller is admin
  IF NOT EXISTS (
    SELECT 1 FROM public.team_auth
    WHERE team_auth.team_name = '__admin__'
      AND password_hash = extensions.crypt(p_admin_pass, password_hash)
  ) THEN
    RETURN;
  END IF;
  RETURN QUERY
    SELECT r.id, r.team_name, r.requester_name, r.reason, r.created_at
    FROM public.password_reset_requests r
    WHERE r.status = 'pending'
    ORDER BY r.created_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_pending_reset_requests(TEXT) TO anon;

-- 11. RPC: Admin rejects a password reset request
CREATE OR REPLACE FUNCTION public.admin_reject_reset_request(p_admin_pass TEXT, p_request_id INT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  -- Verify caller is admin
  IF NOT EXISTS (
    SELECT 1 FROM public.team_auth
    WHERE team_name = '__admin__'
      AND password_hash = extensions.crypt(p_admin_pass, password_hash)
  ) THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;
  UPDATE public.password_reset_requests
  SET status = 'rejected', reviewed_by = '__admin__', reviewed_at = NOW()
  WHERE id = p_request_id AND status = 'pending';
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_reject_reset_request(TEXT, INT) TO anon;

-- ============================================
-- READ-ONLY TEAM ADMIN  (viewer password per team)
-- ============================================
-- Adds a SECOND password per team for a read-only "team admin":
--   * member password (existing password_hash) → full edit, UNCHANGED.
--   * viewer password (new viewer_password_hash) → read & view only.
-- Nothing existing is modified: verify_team_login and member passwords stay intact.

-- 12. ADD the read-only password column (nullable, safe to re-run)
ALTER TABLE public.team_auth
  ADD COLUMN IF NOT EXISTS viewer_password_hash TEXT;

-- 13. NEW RPC: returns the role for a team + password
--     'member' = normal editor (matches password_hash)
--     'viewer' = read-only team admin (matches viewer_password_hash)
--     NULL     = wrong password
CREATE OR REPLACE FUNCTION public.verify_team_role(p_team TEXT, p_password TEXT)
RETURNS TEXT
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
  SELECT CASE
    WHEN EXISTS (
      SELECT 1 FROM public.team_auth
      WHERE team_name = p_team
        AND password_hash = extensions.crypt(p_password, password_hash)
    ) THEN 'member'
    WHEN EXISTS (
      SELECT 1 FROM public.team_auth
      WHERE team_name = p_team
        AND viewer_password_hash IS NOT NULL
        AND viewer_password_hash = extensions.crypt(p_password, viewer_password_hash)
    ) THEN 'viewer'
    ELSE NULL
  END;
$$;

GRANT EXECUTE ON FUNCTION public.verify_team_role(TEXT, TEXT) TO anon;

-- 14. SEED read-only (team admin) passwords — one per team.
--     Re-run any line to change a team's read-only password later.
UPDATE public.team_auth SET viewer_password_hash = extensions.crypt('ibriadmin',     extensions.gen_salt('bf')) WHERE team_name = 'Ibri';
UPDATE public.team_auth SET viewer_password_hash = extensions.crypt('wadiadmin',     extensions.gen_salt('bf')) WHERE team_name = 'Wadi Alain';
UPDATE public.team_auth SET viewer_password_hash = extensions.crypt('araqiadmin',    extensions.gen_salt('bf')) WHERE team_name = 'Araqi';
UPDATE public.team_auth SET viewer_password_hash = extensions.crypt('hijermatadmin', extensions.gen_salt('bf')) WHERE team_name = 'Hijermat';
UPDATE public.team_auth SET viewer_password_hash = extensions.crypt('dankadmin',     extensions.gen_salt('bf')) WHERE team_name = 'Dank';
UPDATE public.team_auth SET viewer_password_hash = extensions.crypt('yanquladmin',   extensions.gen_salt('bf')) WHERE team_name = 'Yanqul';
UPDATE public.team_auth SET viewer_password_hash = extensions.crypt('hamraadmin',    extensions.gen_salt('bf')) WHERE team_name = 'Hamra AlDaroo';
UPDATE public.team_auth SET viewer_password_hash = extensions.crypt('masrooqadmin',  extensions.gen_salt('bf')) WHERE team_name = 'Masrooq';
-- ============================================
CREATE OR REPLACE FUNCTION public.admin_reject_reset_request(p_admin_pass TEXT, p_request_id INT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.team_auth
    WHERE team_name = '__admin__'
      AND password_hash = extensions.crypt(p_admin_pass, password_hash)
  ) THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;
  UPDATE public.password_reset_requests
  SET status = 'rejected', reviewed_by = '__admin__', reviewed_at = NOW()
  WHERE id = p_request_id AND status = 'pending';
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_reject_reset_request(TEXT, INT) TO anon;
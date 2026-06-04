-- ============================================
-- TRANSFORMER MANAGEMENT - SUPABASE SCHEMA
-- ============================================

-- 1. CREATE TRANSFORMERS TABLE
CREATE TABLE public.transformers (
  uid TEXT PRIMARY KEY NOT NULL,
  team TEXT NOT NULL DEFAULT 'default',
  type TEXT NOT NULL,
  tx_id TEXT NOT NULL,
  station TEXT NOT NULL,
  hv_feeder TEXT,
  capacity NUMERIC NOT NULL,
  outputs INTEGER NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(team, tx_id)
);

-- 2. CREATE LOADINGS TABLE
CREATE TABLE public.loadings (
  uid TEXT NOT NULL,
  reading_round INTEGER NOT NULL DEFAULT 1,
  team TEXT NOT NULL DEFAULT 'default',
  volt JSONB DEFAULT '{}',
  pf NUMERIC DEFAULT 0.9,
  volt_saved_at TIMESTAMPTZ,
  feeders JSONB DEFAULT '[]',
  tap_no TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (uid, reading_round),
  FOREIGN KEY (uid) REFERENCES transformers(uid) ON DELETE CASCADE
);

-- ============================================
-- MIGRATION: Run this on existing DB (one time)
-- ============================================
-- ALTER TABLE public.loadings ADD COLUMN reading_round INTEGER NOT NULL DEFAULT 1;
-- ALTER TABLE public.loadings DROP CONSTRAINT loadings_pkey;
-- ALTER TABLE public.loadings ADD PRIMARY KEY (uid, reading_round);
-- ALTER TABLE public.loadings ADD COLUMN tap_no TEXT;

-- 3. CREATE INDEXES FOR BETTER PERFORMANCE
CREATE INDEX idx_transformers_team ON transformers(team);
CREATE INDEX idx_transformers_uid ON transformers(uid);
CREATE INDEX idx_loadings_team ON loadings(team);
CREATE INDEX idx_loadings_uid ON loadings(uid);
CREATE INDEX idx_loadings_updated ON loadings(updated_at DESC);

-- ============================================
-- ROW LEVEL SECURITY (RLS) POLICIES
-- ============================================

-- Enable RLS on both tables
ALTER TABLE public.transformers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.loadings ENABLE ROW LEVEL SECURITY;

-- TRANSFORMERS TABLE POLICIES

-- Policy: Allow SELECT for users in the same team or admin
CREATE POLICY "select_transformers_by_team"
ON public.transformers FOR SELECT
USING (
  team = current_setting('app.current_team')::text OR 
  current_setting('app.is_admin')::boolean = true
);

-- Policy: Allow INSERT only for non-admin users (they insert their own team data)
CREATE POLICY "insert_transformers_own_team"
ON public.transformers FOR INSERT
WITH CHECK (
  team = current_setting('app.current_team')::text
);

-- Policy: Allow UPDATE only for non-admin users
CREATE POLICY "update_transformers_own_team"
ON public.transformers FOR UPDATE
USING (
  team = current_setting('app.current_team')::text OR 
  current_setting('app.is_admin')::boolean = true
)
WITH CHECK (
  team = current_setting('app.current_team')::text OR 
  current_setting('app.is_admin')::boolean = true
);

-- Policy: Allow DELETE only for admin
CREATE POLICY "delete_transformers_admin_only"
ON public.transformers FOR DELETE
USING (current_setting('app.is_admin')::boolean = true);

-- LOADINGS TABLE POLICIES

-- Policy: Allow SELECT for users in the same team or admin
CREATE POLICY "select_loadings_by_team"
ON public.loadings FOR SELECT
USING (
  team = current_setting('app.current_team')::text OR 
  current_setting('app.is_admin')::boolean = true
);

-- Policy: Allow INSERT/UPDATE for users in the same team
CREATE POLICY "insert_update_loadings_own_team"
ON public.loadings FOR INSERT
WITH CHECK (
  team = current_setting('app.current_team')::text
);

CREATE POLICY "update_loadings_own_team"
ON public.loadings FOR UPDATE
USING (
  team = current_setting('app.current_team')::text OR 
  current_setting('app.is_admin')::boolean = true
)
WITH CHECK (
  team = current_setting('app.current_team')::text OR 
  current_setting('app.is_admin')::boolean = true
);

-- Policy: Allow DELETE only for admin
CREATE POLICY "delete_loadings_admin_only"
ON public.loadings FOR DELETE
USING (current_setting('app.is_admin')::boolean = true);

-- ============================================
-- GRANT PERMISSIONS TO ANON ROLE
-- ============================================

GRANT USAGE ON SCHEMA public TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.transformers TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.loadings TO anon;

-- ============================================
-- SAMPLE DATA (OPTIONAL - FOR TESTING)
-- ============================================

-- INSERT INTO public.transformers (uid, team, type, tx_id, station, hv_feeder, capacity, outputs)
-- VALUES 
--   ('a1', 'Ibri', 'أرضي', 'TR-001', 'محطة الشمال', 'F-01', 500, 6),
--   ('a2', 'Wadi Alain', 'معلق', 'TR-002', 'محطة الجنوب', 'F-02', 1600, 4),
--   ('a3', 'Araqi', 'أرضي', 'TR-003', 'محطة الوسط', 'F-03', 250, 8);

-- INSERT INTO public.loadings (uid, team, volt, pf, volt_saved_at, feeders)
-- VALUES 
--   ('a1', 'Ibri', '{"vL1N": "231", "vL2N": "229", "vL3N": "230"}', 0.9, NOW(), '[]'),
--   ('a2', 'Wadi Alain', '{"vL1N": "230", "vL2N": "230", "vL3N": "230"}', 0.92, NOW(), '[]'),
--   ('a3', 'Araqi', '{"vL1N": "232", "vL2N": "228", "vL3N": "229"}', 0.88, NOW(), '[]');

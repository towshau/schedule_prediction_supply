-- Create rolling_schedule_preferences table
-- This table supports the 12-week rolling window system with auto-extend

CREATE TABLE IF NOT EXISTS rolling_schedule_preferences (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    staff_id UUID NOT NULL REFERENCES staff_database(id) ON DELETE CASCADE,
    period_id UUID REFERENCES schedule_periods(id),  -- Links to period for audit
    block TEXT NOT NULL,  -- MON_EARLY, TUE_MID, etc.
    preference_type TEXT NOT NULL,  -- HARD, SOFT, PREFERRED
    effective_date DATE NOT NULL,  -- When preference starts
    end_date DATE,  -- When it ends (NULL = indefinite)
    is_active BOOLEAN DEFAULT true,  -- false = soft-deleted/superseded
    superseded_by UUID REFERENCES rolling_schedule_preferences(id),  -- Audit trail
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    coach_name TEXT,  -- Denormalized for easier querying
    source TEXT DEFAULT 'manual'  -- 'synced', 'migrated', 'manual', 'auto_extended'
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_rolling_prefs_staff_id ON rolling_schedule_preferences(staff_id);
CREATE INDEX IF NOT EXISTS idx_rolling_prefs_period_id ON rolling_schedule_preferences(period_id);
CREATE INDEX IF NOT EXISTS idx_rolling_prefs_effective_date ON rolling_schedule_preferences(effective_date);
CREATE INDEX IF NOT EXISTS idx_rolling_prefs_active ON rolling_schedule_preferences(is_active) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_rolling_prefs_date_range ON rolling_schedule_preferences(staff_id, effective_date, end_date) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_rolling_prefs_source ON rolling_schedule_preferences(source);

-- Create or verify update function exists
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for auto-updating updated_at
CREATE TRIGGER update_rolling_preferences_updated_at
    BEFORE UPDATE ON rolling_schedule_preferences
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

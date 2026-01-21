-- Execute one-time migration of existing schedule_preferences
-- to rolling_schedule_preferences

-- Run the migration
SELECT * FROM migrate_period_preferences();

-- Verify migration results
SELECT 
    COUNT(*) as total_rolling_prefs,
    COUNT(DISTINCT staff_id) as unique_coaches,
    COUNT(DISTINCT period_id) as unique_periods,
    COUNT(DISTINCT source) as unique_sources
FROM rolling_schedule_preferences;

-- Show breakdown by source
SELECT 
    source,
    COUNT(*) as count,
    MIN(effective_date) as earliest_date,
    MAX(effective_date) as latest_date
FROM rolling_schedule_preferences
GROUP BY source
ORDER BY source;

-- Show breakdown by coach
SELECT 
    coach_name,
    COUNT(*) as total_preferences,
    COUNT(DISTINCT block) as unique_blocks
FROM rolling_schedule_preferences
WHERE is_active = true
GROUP BY coach_name
ORDER BY coach_name;

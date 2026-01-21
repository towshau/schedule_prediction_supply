-- ============================================================================
-- MONITORING QUERIES FOR ROLLING SCHEDULE PREFERENCES
-- ============================================================================
-- Use these queries to monitor the auto-extend cron job and system health

-- ============================================================================
-- 1. CHECK CRON JOB STATUS
-- ============================================================================
-- View scheduled cron jobs
SELECT 
    jobid,
    jobname,
    schedule,
    command,
    nodename,
    nodeport,
    database,
    username,
    active
FROM cron.job
WHERE jobname = 'auto-extend-preferences';

-- View recent cron job executions
SELECT 
    runid,
    jobid,
    start_time,
    end_time,
    status,
    return_message,
    (end_time - start_time) as duration
FROM cron.job_run_details 
WHERE jobid = (SELECT jobid FROM cron.job WHERE jobname = 'auto-extend-preferences')
ORDER BY start_time DESC 
LIMIT 20;

-- ============================================================================
-- 2. CHECK 12-WEEK COVERAGE STATUS
-- ============================================================================
-- See which coaches have full 12-week coverage
SELECT 
    s.coach_name,
    COUNT(DISTINCT rsp.block) as covered_blocks,
    MAX(rsp.end_date) as furthest_coverage,
    CURRENT_DATE + INTERVAL '12 weeks' as target_date,
    MAX(rsp.end_date) - CURRENT_DATE as days_covered,
    CASE 
        WHEN MAX(rsp.end_date) >= CURRENT_DATE + INTERVAL '12 weeks' 
        THEN '✅ OK' 
        ELSE '⚠️ NEEDS EXTENSION' 
    END as status
FROM staff_database s
LEFT JOIN rolling_schedule_preferences rsp 
    ON s.id = rsp.staff_id 
    AND rsp.is_active = true
WHERE s.staff_status = 'active'
GROUP BY s.coach_name
ORDER BY MAX(rsp.end_date);

-- ============================================================================
-- 3. VIEW RECENT AUTO-EXTENSIONS
-- ============================================================================
-- See recently auto-extended preferences
SELECT 
    coach_name,
    block,
    preference_type,
    effective_date,
    end_date,
    created_at,
    AGE(NOW(), created_at) as age
FROM rolling_schedule_preferences
WHERE source = 'auto_extended'
ORDER BY created_at DESC
LIMIT 50;

-- ============================================================================
-- 4. COUNT PREFERENCES BY SOURCE
-- ============================================================================
-- Breakdown of where preferences came from
SELECT 
    source,
    COUNT(*) as total_count,
    COUNT(CASE WHEN is_active THEN 1 END) as active_count,
    COUNT(CASE WHEN NOT is_active THEN 1 END) as inactive_count,
    MIN(effective_date) as earliest_date,
    MAX(effective_date) as latest_date
FROM rolling_schedule_preferences
GROUP BY source
ORDER BY source;

-- ============================================================================
-- 5. ALERT: COACHES WITH GAPS
-- ============================================================================
-- Find coaches who don't have 12-week coverage (needs immediate attention)
SELECT 
    s.coach_name,
    s.id as coach_id,
    MAX(rsp.end_date) as coverage_end,
    CURRENT_DATE + INTERVAL '12 weeks' as should_cover_until,
    CURRENT_DATE + INTERVAL '12 weeks' - MAX(rsp.end_date) as days_short
FROM staff_database s
LEFT JOIN rolling_schedule_preferences rsp 
    ON s.id = rsp.staff_id 
    AND rsp.is_active = true
WHERE s.staff_status = 'active'
    AND (MAX(rsp.end_date) < CURRENT_DATE + INTERVAL '12 weeks' 
         OR MAX(rsp.end_date) IS NULL)
GROUP BY s.coach_name, s.id
ORDER BY days_short DESC;

-- ============================================================================
-- 6. COVERAGE BY TIME BLOCK
-- ============================================================================
-- See how many coaches available for each time block (next 12 weeks)
SELECT 
    rsp.block,
    COUNT(DISTINCT rsp.staff_id) as num_coaches,
    STRING_AGG(DISTINCT rsp.coach_name, ', ' ORDER BY rsp.coach_name) as coaches,
    COUNT(*) as total_preferences
FROM rolling_schedule_preferences rsp
JOIN staff_database sd ON rsp.staff_id = sd.id
WHERE rsp.effective_date <= CURRENT_DATE + INTERVAL '12 weeks'
    AND (rsp.end_date IS NULL OR rsp.end_date >= CURRENT_DATE)
    AND rsp.is_active = true
    AND sd.staff_status = 'active'
GROUP BY rsp.block
ORDER BY rsp.block;

-- ============================================================================
-- 7. AUDIT TRAIL: RECENT CHANGES
-- ============================================================================
-- See recent preference changes (overrides, new submissions)
SELECT 
    coach_name,
    block,
    preference_type,
    source,
    effective_date,
    end_date,
    is_active,
    created_at,
    CASE 
        WHEN is_active THEN 'Active'
        ELSE 'Superseded'
    END as status
FROM rolling_schedule_preferences
WHERE created_at >= NOW() - INTERVAL '7 days'
ORDER BY created_at DESC;

-- ============================================================================
-- 8. SYSTEM HEALTH SUMMARY
-- ============================================================================
-- Overall system health dashboard
SELECT 
    'Total Preferences' as metric,
    COUNT(*)::TEXT as value
FROM rolling_schedule_preferences

UNION ALL

SELECT 
    'Active Preferences',
    COUNT(*)::TEXT
FROM rolling_schedule_preferences
WHERE is_active = true

UNION ALL

SELECT 
    'Active Coaches with Preferences',
    COUNT(DISTINCT s.coach_name)::TEXT
FROM staff_database s
JOIN rolling_schedule_preferences rsp ON s.id = rsp.staff_id
WHERE s.staff_status = 'active'
    AND rsp.is_active = true

UNION ALL

SELECT 
    'Coaches Needing Extension',
    COUNT(DISTINCT s.coach_name)::TEXT
FROM staff_database s
LEFT JOIN rolling_schedule_preferences rsp 
    ON s.id = rsp.staff_id 
    AND rsp.is_active = true
WHERE s.staff_status = 'active'
    AND (MAX(rsp.end_date) < CURRENT_DATE + INTERVAL '12 weeks' 
         OR MAX(rsp.end_date) IS NULL)
GROUP BY s.coach_name

UNION ALL

SELECT 
    'Auto-Extended This Week',
    COUNT(*)::TEXT
FROM rolling_schedule_preferences
WHERE source = 'auto_extended'
    AND created_at >= NOW() - INTERVAL '7 days'

UNION ALL

SELECT 
    'Last Cron Run',
    TO_CHAR(MAX(start_time), 'YYYY-MM-DD HH24:MI:SS')
FROM cron.job_run_details
WHERE jobid = (SELECT jobid FROM cron.job WHERE jobname = 'auto-extend-preferences');

-- ============================================================================
-- 9. WEEKLY EXTENSION REPORT (Run after cron job)
-- ============================================================================
-- Generate report of what was extended in the last run
WITH recent_extensions AS (
    SELECT 
        coach_name,
        block,
        preference_type,
        effective_date,
        end_date,
        created_at
    FROM rolling_schedule_preferences
    WHERE source = 'auto_extended'
        AND created_at >= NOW() - INTERVAL '1 hour'  -- Adjust based on when cron runs
)
SELECT 
    coach_name,
    COUNT(*) as blocks_extended,
    STRING_AGG(block, ', ' ORDER BY block) as blocks,
    MIN(effective_date) as extension_start,
    MAX(end_date) as extension_end
FROM recent_extensions
GROUP BY coach_name
ORDER BY coach_name;

-- ============================================================================
-- 10. MANUAL FIX: EXTEND SPECIFIC COACH
-- ============================================================================
-- If a coach is missing coverage, manually extend them
-- Replace 'COACH_NAME' with actual coach name
/*
WITH coach_to_extend AS (
    SELECT id, coach_name FROM staff_database WHERE coach_name = 'Aaron Kidd'
),
latest_prefs AS (
    SELECT DISTINCT ON (rsp.block)
        rsp.block,
        rsp.preference_type,
        rsp.end_date
    FROM rolling_schedule_preferences rsp
    JOIN coach_to_extend c ON rsp.staff_id = c.id
    WHERE rsp.is_active = true
    ORDER BY rsp.block, rsp.effective_date DESC
)
INSERT INTO rolling_schedule_preferences (
    staff_id,
    block,
    preference_type,
    effective_date,
    end_date,
    coach_name,
    source
)
SELECT 
    c.id,
    lp.block,
    lp.preference_type,
    lp.end_date + INTERVAL '1 day',
    CURRENT_DATE + INTERVAL '12 weeks',
    c.coach_name,
    'manual_extension'
FROM latest_prefs lp
CROSS JOIN coach_to_extend c
WHERE lp.end_date < CURRENT_DATE + INTERVAL '12 weeks'
RETURNING coach_name, block, effective_date, end_date;
*/

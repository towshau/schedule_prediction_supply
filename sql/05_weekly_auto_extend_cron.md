# Weekly Auto-Extend Cron Job Setup

## Overview

The rolling preference system requires a weekly cron job that runs the `auto_extend_preferences()` function to maintain the 12-week rolling window.

## Recommended Schedule

**Run every Monday at 6:00 AM** (before coaches start their day)

## Setup Options

### Option 1: Supabase Database Webhooks (Recommended)

Use Supabase's built-in pg_cron extension:

```sql
-- Enable pg_cron extension (if not already enabled)
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Schedule weekly auto-extend job
-- Runs every Monday at 6:00 AM UTC
SELECT cron.schedule(
    'auto-extend-preferences',  -- Job name
    '0 6 * * 1',                -- Cron expression: Every Monday at 6 AM
    $$SELECT * FROM auto_extend_preferences()$$
);

-- View scheduled jobs
SELECT * FROM cron.job;

-- View job run history
SELECT * FROM cron.job_run_details 
WHERE jobname = 'auto-extend-preferences'
ORDER BY start_time DESC 
LIMIT 10;
```

### Option 2: External Cron (Linux/macOS)

If managing from external server:

```bash
# Edit crontab
crontab -e

# Add this line (runs Monday 6 AM)
0 6 * * 1 psql $DATABASE_URL -c "SELECT * FROM auto_extend_preferences();"
```

### Option 3: GitHub Actions

Create `.github/workflows/auto_extend.yml`:

```yaml
name: Weekly Auto-Extend Preferences

on:
  schedule:
    # Every Monday at 6:00 AM UTC
    - cron: '0 6 * * 1'
  workflow_dispatch:  # Allow manual trigger

jobs:
  auto-extend:
    runs-on: ubuntu-latest
    steps:
      - name: Run Auto-Extend Function
        env:
          DATABASE_URL: ${{ secrets.SUPABASE_DB_URL }}
        run: |
          psql $DATABASE_URL -c "SELECT * FROM auto_extend_preferences();"
```

### Option 4: Retool Scheduled Query

1. Go to Retool
2. Create new Query: `auto_extend_query`
3. Set query to: `SELECT * FROM auto_extend_preferences()`
4. Click "Schedule" tab
5. Set schedule: "Weekly on Monday at 6:00 AM"
6. Enable notifications on failure

## Testing

### Test the function manually:

```sql
-- Run the auto-extend function
SELECT * FROM auto_extend_preferences();

-- Expected output:
-- staff_id | coach_name | blocks_extended | new_end_date
-- Returns list of coaches whose preferences were extended
```

### Verify results:

```sql
-- Check that all active coaches have 12-week coverage
SELECT 
    s.coach_name,
    MAX(rsp.end_date) as coverage_end,
    CURRENT_DATE + INTERVAL '12 weeks' as target_date,
    CASE 
        WHEN MAX(rsp.end_date) >= CURRENT_DATE + INTERVAL '12 weeks' 
        THEN 'OK' 
        ELSE 'NEEDS EXTENSION' 
    END as status
FROM staff_database s
LEFT JOIN rolling_schedule_preferences rsp 
    ON s.id = rsp.staff_id 
    AND rsp.is_active = true
WHERE s.staff_status = 'active'
GROUP BY s.coach_name
ORDER BY coverage_end;
```

## Monitoring

### Check job execution:

```sql
-- Find coaches that need extension
SELECT 
    s.coach_name,
    COUNT(DISTINCT rsp.block) as covered_blocks,
    MAX(rsp.end_date) as furthest_date
FROM staff_database s
LEFT JOIN rolling_schedule_preferences rsp 
    ON s.id = rsp.staff_id 
    AND rsp.is_active = true
WHERE s.staff_status = 'active'
GROUP BY s.coach_name
HAVING MAX(rsp.end_date) < CURRENT_DATE + INTERVAL '12 weeks';
```

### View auto-extended preferences:

```sql
-- See recent auto-extensions
SELECT 
    coach_name,
    block,
    effective_date,
    end_date,
    created_at
FROM rolling_schedule_preferences
WHERE source = 'auto_extended'
ORDER BY created_at DESC
LIMIT 50;
```

## Alerts & Notifications

### Set up alerts for:

1. **Job failure** - If cron job doesn't run
2. **Coverage gaps** - If any coach has < 12 week coverage
3. **No extensions made** - If function returns 0 results (unexpected)

### Example alert query:

```sql
-- Alert if any coach has less than 12-week coverage
SELECT 
    s.coach_name,
    s.email,  -- If available
    MAX(rsp.end_date) as coverage_end,
    CURRENT_DATE + INTERVAL '12 weeks' - MAX(rsp.end_date) as days_short
FROM staff_database s
LEFT JOIN rolling_schedule_preferences rsp 
    ON s.id = rsp.staff_id 
    AND rsp.is_active = true
WHERE s.staff_status = 'active'
    AND (MAX(rsp.end_date) < CURRENT_DATE + INTERVAL '12 weeks' 
         OR MAX(rsp.end_date) IS NULL)
GROUP BY s.coach_name, s.email;
```

## Troubleshooting

### Function returns no results:
- This is normal if all coaches already have 12-week coverage
- Verify by running the coverage check query above

### Function fails:
```sql
-- Check for errors in logs
SELECT * FROM auto_extend_preferences();
-- Review error message

-- Common issues:
-- 1. staff_status column name mismatch
-- 2. Missing coaches in staff_database
-- 3. Database connection timeout
```

### Manual fix if cron fails:

```sql
-- Manually extend all preferences that need it
SELECT * FROM auto_extend_preferences();
```

## Performance

- Expected execution time: < 5 seconds (for ~15 coaches)
- Database load: Minimal (single transaction)
- Recommended run time: Off-peak hours (early morning)

## Next Steps

1. Choose setup option (Supabase pg_cron recommended)
2. Configure cron schedule
3. Test manually first time
4. Set up monitoring/alerts
5. Document in team runbook

## Support

If issues arise:
- Check Supabase logs: Database > Logs
- Review job history (if using pg_cron)
- Contact: Biomap Operations Team

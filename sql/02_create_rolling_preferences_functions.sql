-- Core functions for rolling schedule preference system

-- ============================================================================
-- Function 1: Override Future Preferences
-- ============================================================================
-- When a coach submits a new preference, this replaces ALL future preferences
-- from the effective_date forward
CREATE OR REPLACE FUNCTION override_rolling_preferences(
    p_staff_id UUID,
    p_block TEXT,
    p_preference_type TEXT,
    p_effective_date DATE,
    p_coach_name TEXT
) RETURNS UUID AS $$
DECLARE
    v_new_preference_id UUID;
BEGIN
    -- Step 1: Soft delete all future preferences for this coach from effective_date forward
    UPDATE rolling_schedule_preferences
    SET 
        is_active = false,
        end_date = p_effective_date - INTERVAL '1 day',
        updated_at = NOW()
    WHERE staff_id = p_staff_id
        AND effective_date >= p_effective_date
        AND is_active = true;
    
    -- Step 2: Insert new preference
    INSERT INTO rolling_schedule_preferences (
        staff_id, block, preference_type, 
        effective_date, end_date, coach_name
    ) VALUES (
        p_staff_id, p_block, p_preference_type,
        p_effective_date, p_effective_date + INTERVAL '12 weeks', p_coach_name
    ) RETURNING id INTO v_new_preference_id;
    
    -- Step 3: Update superseded_by references for audit trail
    UPDATE rolling_schedule_preferences
    SET superseded_by = v_new_preference_id
    WHERE staff_id = p_staff_id
        AND effective_date >= p_effective_date
        AND is_active = false
        AND superseded_by IS NULL;
    
    RETURN v_new_preference_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Function 2: Query Active Preferences for Specific Date
-- ============================================================================
-- Retrieve what preferences are active on a given date
CREATE OR REPLACE FUNCTION get_active_preferences_for_date(
    p_date DATE
) RETURNS TABLE (
    id UUID,
    staff_id UUID,
    coach_name TEXT,
    block TEXT,
    preference_type TEXT,
    effective_date DATE,
    end_date DATE
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        rsp.id,
        rsp.staff_id,
        rsp.coach_name,
        rsp.block,
        rsp.preference_type,
        rsp.effective_date,
        rsp.end_date
    FROM rolling_schedule_preferences rsp
    WHERE rsp.effective_date <= p_date
        AND (rsp.end_date IS NULL OR rsp.end_date >= p_date)
        AND rsp.is_active = true
    ORDER BY rsp.effective_date DESC;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Function 3: Migrate Period Preferences (One-Time)
-- ============================================================================
-- Convert existing schedule_preferences to rolling_schedule_preferences
CREATE OR REPLACE FUNCTION migrate_period_preferences()
RETURNS TABLE (
    migrated_count INT,
    period_label TEXT,
    period_start DATE
) AS $$
BEGIN
    RETURN QUERY
    WITH inserted AS (
        INSERT INTO rolling_schedule_preferences (
            staff_id,
            period_id,
            block,
            preference_type,
            effective_date,
            end_date,
            coach_name,
            source
        )
        SELECT 
            sp.staff_id,
            sp.period_id,
            sp.block::TEXT,  -- Cast enum to text
            sp.preference_type::TEXT,  -- Cast enum to text
            COALESCE(periods.week_start, sp.submitted_at::DATE) as effective_date,
            COALESCE(periods.week_start, sp.submitted_at::DATE) + INTERVAL '12 weeks' as end_date,
            sp.coach_name,
            'migrated' as source
        FROM schedule_preferences sp
        LEFT JOIN schedule_periods periods ON sp.period_id = periods.id
        WHERE NOT EXISTS (
            SELECT 1 FROM rolling_schedule_preferences rsp
            WHERE rsp.staff_id = sp.staff_id
                AND rsp.period_id = sp.period_id
                AND rsp.block = sp.block::TEXT
        )
        RETURNING staff_id, period_id
    )
    SELECT 
        COUNT(*)::INT as migrated_count,
        periods.label,
        periods.week_start as period_start
    FROM inserted i
    LEFT JOIN schedule_periods periods ON i.period_id = periods.id
    GROUP BY periods.label, periods.week_start
    ORDER BY periods.week_start DESC;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Function 4: Auto-Extend Weekly Preferences
-- ============================================================================
-- Runs weekly (Monday mornings) to maintain 12-week coverage
CREATE OR REPLACE FUNCTION auto_extend_preferences()
RETURNS TABLE (
    staff_id UUID,
    coach_name TEXT,
    blocks_extended INT,
    new_end_date DATE
) AS $$
DECLARE
    v_target_date DATE := CURRENT_DATE + INTERVAL '12 weeks';
    v_coach RECORD;
    v_last_pref RECORD;
    v_extended_count INT;
BEGIN
    -- For each active coach
    FOR v_coach IN 
        SELECT s.id, s.coach_name
        FROM staff_database s
        WHERE s.staff_status = 'active'
    LOOP
        v_extended_count := 0;
        
        -- Get their latest active preference pattern
        FOR v_last_pref IN
            SELECT DISTINCT ON (block) 
                block, preference_type, end_date
            FROM rolling_schedule_preferences
            WHERE staff_id = v_coach.id
                AND is_active = true
            ORDER BY block, effective_date DESC
        LOOP
            -- If this preference doesn't cover week 12, extend it
            IF v_last_pref.end_date < v_target_date THEN
                INSERT INTO rolling_schedule_preferences (
                    staff_id,
                    block,
                    preference_type,
                    effective_date,
                    end_date,
                    coach_name,
                    source
                ) VALUES (
                    v_coach.id,
                    v_last_pref.block,
                    v_last_pref.preference_type,
                    v_last_pref.end_date + INTERVAL '1 day',  -- Start where previous ended
                    v_target_date,
                    v_coach.coach_name,
                    'auto_extended'
                );
                
                v_extended_count := v_extended_count + 1;
            END IF;
        END LOOP;
        
        -- Return result for this coach if any extensions were made
        IF v_extended_count > 0 THEN
            staff_id := v_coach.id;
            coach_name := v_coach.coach_name;
            blocks_extended := v_extended_count;
            new_end_date := v_target_date;
            RETURN NEXT;
        END IF;
    END LOOP;
    
    RETURN;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- Function 5: Sync Period Submissions to Rolling (Trigger Function)
-- ============================================================================
-- Automatically creates rolling preferences when coach submits via existing form
CREATE OR REPLACE FUNCTION sync_to_rolling()
RETURNS TRIGGER AS $$
DECLARE
    v_effective_date DATE;
    v_end_date DATE;
BEGIN
    -- Get the period's start date for effective_date
    SELECT week_start INTO v_effective_date
    FROM schedule_periods
    WHERE id = NEW.period_id;
    
    -- If no period found, use submitted_at date
    IF v_effective_date IS NULL THEN
        v_effective_date := NEW.submitted_at::DATE;
    END IF;
    
    -- Calculate end date (12 weeks from effective date)
    v_end_date := v_effective_date + INTERVAL '12 weeks';
    
    -- Insert into rolling_schedule_preferences
    INSERT INTO rolling_schedule_preferences (
        staff_id,
        period_id,
        block,
        preference_type,
        effective_date,
        end_date,
        coach_name,
        source
    ) VALUES (
        NEW.staff_id,
        NEW.period_id,
        NEW.block::TEXT,  -- Cast enum to text
        NEW.preference_type::TEXT,  -- Cast enum to text
        v_effective_date,
        v_end_date,
        NEW.coach_name,
        'synced'
    );
    
    -- Return NEW to allow the original INSERT to proceed
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

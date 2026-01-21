-- Create trigger on schedule_preferences table
-- Automatically syncs new form submissions to rolling_schedule_preferences

DROP TRIGGER IF EXISTS trigger_sync_to_rolling ON schedule_preferences;

CREATE TRIGGER trigger_sync_to_rolling
    AFTER INSERT ON schedule_preferences
    FOR EACH ROW
    EXECUTE FUNCTION sync_to_rolling();

-- Verify trigger was created
SELECT 
    trigger_name,
    event_manipulation,
    event_object_table,
    action_statement
FROM information_schema.triggers
WHERE trigger_name = 'trigger_sync_to_rolling';

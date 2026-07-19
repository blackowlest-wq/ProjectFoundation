-- Task 1 approval audit migration for an existing isolated Oracle test schema.
-- The base schema-daily-report.sql contains these columns for fresh schemas.
DECLARE
    column_count NUMBER;
BEGIN
    SELECT COUNT(*) INTO column_count
    FROM user_tab_columns
    WHERE table_name = 'DAILY_REPORTS' AND column_name = 'APPROVER_USER_ID';
    IF column_count = 0 THEN
        EXECUTE IMMEDIATE 'ALTER TABLE daily_reports ADD (approver_user_id VARCHAR2(20 CHAR))';
    END IF;

    SELECT COUNT(*) INTO column_count
    FROM user_tab_columns
    WHERE table_name = 'DAILY_REPORTS' AND column_name = 'APPROVER_NAME';
    IF column_count = 0 THEN
        EXECUTE IMMEDIATE 'ALTER TABLE daily_reports ADD (approver_name VARCHAR2(120 CHAR))';
    END IF;

    SELECT COUNT(*) INTO column_count
    FROM user_tab_columns
    WHERE table_name = 'DAILY_REPORTS' AND column_name = 'APPROVED_AT';
    IF column_count = 0 THEN
        EXECUTE IMMEDIATE 'ALTER TABLE daily_reports ADD (approved_at TIMESTAMP WITH LOCAL TIME ZONE)';
    END IF;
END;
/

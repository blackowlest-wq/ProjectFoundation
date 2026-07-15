whenever sqlerror exit sql.sqlcode
set heading off feedback off pagesize 0 verify off echo off

DECLARE
    report_count NUMBER;
BEGIN
    SELECT COUNT(*)
    INTO report_count
    FROM daily_reports
    WHERE report_id = '&REPORT_ID'
      AND employee_user_id = 'U001'
      AND report_date = DATE '2099-12-01'
      AND approval_status = 'PENDING';

    IF report_count <> 1 THEN
        raise_application_error(-20001, 'Oracle E2E report verification failed.');
    END IF;
END;
/

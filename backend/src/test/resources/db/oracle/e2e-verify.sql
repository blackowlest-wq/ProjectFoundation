whenever sqlerror exit sql.sqlcode
set heading off feedback off pagesize 0 verify off echo off

DECLARE
    pending_count NUMBER;
    approved_count NUMBER;
    work_item_count NUMBER;
BEGIN
    SELECT COUNT(*)
    INTO pending_count
    FROM daily_reports
    WHERE employee_user_id = 'U001'
      AND report_date = DATE '2099-12-01'
      AND holiday_type = 'PAID_LEAVE'
      AND submitted_at IS NOT NULL
      AND approval_status = 'PENDING';

    IF pending_count <> 1 THEN
        raise_application_error(-20001, 'Oracle E2E pending daily report verification failed.');
    END IF;

    SELECT COUNT(*)
    INTO approved_count
    FROM daily_reports
    WHERE employee_user_id = 'U001'
      AND report_date = DATE '2099-12-02'
      AND holiday_type = 'WORKDAY'
      AND work_minutes = 480
      AND approver_user_id = 'U002'
      AND approver_name = '佐藤 花子'
      AND approved_at IS NOT NULL
      AND approval_status = 'APPROVED';

    IF approved_count <> 1 THEN
        raise_application_error(-20002, 'Oracle E2E approved daily report verification failed.');
    END IF;

    SELECT COUNT(*)
    INTO work_item_count
    FROM daily_report_work_items item
    JOIN daily_reports report ON report.report_id = item.report_id
    WHERE report.employee_user_id = 'U001'
      AND report.report_date = DATE '2099-12-02'
      AND item.project_id = 'P001'
      AND item.work_category_id = 'WC001'
      AND item.work_minutes = 480;

    IF work_item_count <> 1 THEN
        raise_application_error(-20003, 'Oracle E2E work item verification failed.');
    END IF;
END;
/

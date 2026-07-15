DELETE FROM daily_report_work_items
WHERE report_id IN (
    SELECT report_id
    FROM daily_reports
    WHERE employee_user_id = 'U001'
      AND report_date = DATE '2099-12-01'
);

DELETE FROM daily_reports
WHERE employee_user_id = 'U001'
  AND report_date = DATE '2099-12-01';

COMMIT;

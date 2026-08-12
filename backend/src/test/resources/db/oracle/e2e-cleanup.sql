DELETE FROM daily_report_work_items
WHERE report_id IN (
    SELECT report_id
    FROM daily_reports
    WHERE employee_user_id = 'U001'
      AND report_date IN (DATE '2099-12-01', DATE '2099-12-02')
);

DELETE FROM daily_reports
WHERE employee_user_id = 'U001'
  AND report_date IN (DATE '2099-12-01', DATE '2099-12-02');

COMMIT;

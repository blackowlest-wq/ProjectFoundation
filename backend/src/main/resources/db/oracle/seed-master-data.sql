-- Master data seed for Oracle Database.
-- Run after schema-login.sql or schema-daily-report.sql.

MERGE INTO projects target
USING (SELECT 'P001' project_id, 'プロジェクトA' project_name, 1 display_order FROM dual) source
ON (target.project_id = source.project_id)
WHEN MATCHED THEN UPDATE SET target.project_name = source.project_name, target.display_order = source.display_order, target.enabled = 1
WHEN NOT MATCHED THEN INSERT (project_id, project_name, display_order, enabled)
VALUES (source.project_id, source.project_name, source.display_order, 1);

MERGE INTO projects target
USING (SELECT 'P002' project_id, 'プロジェクトB' project_name, 2 display_order FROM dual) source
ON (target.project_id = source.project_id)
WHEN MATCHED THEN UPDATE SET target.project_name = source.project_name, target.display_order = source.display_order, target.enabled = 1
WHEN NOT MATCHED THEN INSERT (project_id, project_name, display_order, enabled)
VALUES (source.project_id, source.project_name, source.display_order, 1);

MERGE INTO work_categories target
USING (SELECT 'WC001' work_category_id, '設計' work_category_name, 1 display_order FROM dual) source
ON (target.work_category_id = source.work_category_id)
WHEN MATCHED THEN UPDATE SET target.work_category_name = source.work_category_name, target.display_order = source.display_order, target.enabled = 1
WHEN NOT MATCHED THEN INSERT (work_category_id, work_category_name, display_order, enabled)
VALUES (source.work_category_id, source.work_category_name, source.display_order, 1);

MERGE INTO work_categories target
USING (SELECT 'WC002' work_category_id, '実装' work_category_name, 2 display_order FROM dual) source
ON (target.work_category_id = source.work_category_id)
WHEN MATCHED THEN UPDATE SET target.work_category_name = source.work_category_name, target.display_order = source.display_order, target.enabled = 1
WHEN NOT MATCHED THEN INSERT (work_category_id, work_category_name, display_order, enabled)
VALUES (source.work_category_id, source.work_category_name, source.display_order, 1);

MERGE INTO work_categories target
USING (SELECT 'WC003' work_category_id, 'テスト' work_category_name, 3 display_order FROM dual) source
ON (target.work_category_id = source.work_category_id)
WHEN MATCHED THEN UPDATE SET target.work_category_name = source.work_category_name, target.display_order = source.display_order, target.enabled = 1
WHEN NOT MATCHED THEN INSERT (work_category_id, work_category_name, display_order, enabled)
VALUES (source.work_category_id, source.work_category_name, source.display_order, 1);

MERGE INTO holiday_types target
USING (SELECT 'WORKDAY' holiday_type, '通常勤務' holiday_type_name, 1 requires_work_time, 1 allows_work_items, 1 display_order FROM dual) source
ON (target.holiday_type = source.holiday_type)
WHEN MATCHED THEN UPDATE SET target.holiday_type_name = source.holiday_type_name, target.requires_work_time = source.requires_work_time, target.allows_work_items = source.allows_work_items, target.display_order = source.display_order, target.enabled = 1
WHEN NOT MATCHED THEN INSERT (holiday_type, holiday_type_name, requires_work_time, allows_work_items, display_order, enabled)
VALUES (source.holiday_type, source.holiday_type_name, source.requires_work_time, source.allows_work_items, source.display_order, 1);

MERGE INTO holiday_types target
USING (SELECT 'HOLIDAY' holiday_type, '休日' holiday_type_name, 0 requires_work_time, 1 allows_work_items, 2 display_order FROM dual) source
ON (target.holiday_type = source.holiday_type)
WHEN MATCHED THEN UPDATE SET target.holiday_type_name = source.holiday_type_name, target.requires_work_time = source.requires_work_time, target.allows_work_items = source.allows_work_items, target.display_order = source.display_order, target.enabled = 1
WHEN NOT MATCHED THEN INSERT (holiday_type, holiday_type_name, requires_work_time, allows_work_items, display_order, enabled)
VALUES (source.holiday_type, source.holiday_type_name, source.requires_work_time, source.allows_work_items, source.display_order, 1);

MERGE INTO holiday_types target
USING (SELECT 'PAID_LEAVE' holiday_type, '有給休暇' holiday_type_name, 0 requires_work_time, 0 allows_work_items, 3 display_order FROM dual) source
ON (target.holiday_type = source.holiday_type)
WHEN MATCHED THEN UPDATE SET target.holiday_type_name = source.holiday_type_name, target.requires_work_time = source.requires_work_time, target.allows_work_items = source.allows_work_items, target.display_order = source.display_order, target.enabled = 1
WHEN NOT MATCHED THEN INSERT (holiday_type, holiday_type_name, requires_work_time, allows_work_items, display_order, enabled)
VALUES (source.holiday_type, source.holiday_type_name, source.requires_work_time, source.allows_work_items, source.display_order, 1);

MERGE INTO holiday_types target
USING (SELECT 'AM_OFF' holiday_type, '午前休' holiday_type_name, 1 requires_work_time, 1 allows_work_items, 4 display_order FROM dual) source
ON (target.holiday_type = source.holiday_type)
WHEN MATCHED THEN UPDATE SET target.holiday_type_name = source.holiday_type_name, target.requires_work_time = source.requires_work_time, target.allows_work_items = source.allows_work_items, target.display_order = source.display_order, target.enabled = 1
WHEN NOT MATCHED THEN INSERT (holiday_type, holiday_type_name, requires_work_time, allows_work_items, display_order, enabled)
VALUES (source.holiday_type, source.holiday_type_name, source.requires_work_time, source.allows_work_items, source.display_order, 1);

MERGE INTO holiday_types target
USING (SELECT 'PM_OFF' holiday_type, '午後休' holiday_type_name, 1 requires_work_time, 1 allows_work_items, 5 display_order FROM dual) source
ON (target.holiday_type = source.holiday_type)
WHEN MATCHED THEN UPDATE SET target.holiday_type_name = source.holiday_type_name, target.requires_work_time = source.requires_work_time, target.allows_work_items = source.allows_work_items, target.display_order = source.display_order, target.enabled = 1
WHEN NOT MATCHED THEN INSERT (holiday_type, holiday_type_name, requires_work_time, allows_work_items, display_order, enabled)
VALUES (source.holiday_type, source.holiday_type_name, source.requires_work_time, source.allows_work_items, source.display_order, 1);

MERGE INTO break_types target
USING (SELECT 'BT001' break_type_id, '標準休憩' break_type_name, 1 display_order FROM dual) source
ON (target.break_type_id = source.break_type_id)
WHEN MATCHED THEN UPDATE SET target.break_type_name = source.break_type_name, target.display_order = source.display_order, target.enabled = 1
WHEN NOT MATCHED THEN INSERT (break_type_id, break_type_name, display_order, enabled)
VALUES (source.break_type_id, source.break_type_name, source.display_order, 1);

MERGE INTO break_types target
USING (SELECT 'BT002' break_type_id, '分割休憩' break_type_name, 2 display_order FROM dual) source
ON (target.break_type_id = source.break_type_id)
WHEN MATCHED THEN UPDATE SET target.break_type_name = source.break_type_name, target.display_order = source.display_order, target.enabled = 1
WHEN NOT MATCHED THEN INSERT (break_type_id, break_type_name, display_order, enabled)
VALUES (source.break_type_id, source.break_type_name, source.display_order, 1);

DELETE FROM break_type_periods WHERE break_type_id IN ('BT001', 'BT002');

INSERT INTO break_type_periods (break_type_id, start_minutes, end_minutes, display_order)
VALUES ('BT001', 720, 780, 1);

INSERT INTO break_type_periods (break_type_id, start_minutes, end_minutes, display_order)
VALUES ('BT002', 720, 780, 1);

INSERT INTO break_type_periods (break_type_id, start_minutes, end_minutes, display_order)
VALUES ('BT002', 1050, 1065, 2);

MERGE INTO work_time_types target
USING (SELECT 'WT001' work_time_type_id, '通常勤務' work_time_type_name, 540 regular_start_minutes, 1080 regular_end_minutes, 1320 night_start_minutes, 300 night_end_minutes, 1 display_order FROM dual) source
ON (target.work_time_type_id = source.work_time_type_id)
WHEN MATCHED THEN UPDATE SET target.work_time_type_name = source.work_time_type_name, target.regular_start_minutes = source.regular_start_minutes, target.regular_end_minutes = source.regular_end_minutes, target.night_start_minutes = source.night_start_minutes, target.night_end_minutes = source.night_end_minutes, target.display_order = source.display_order, target.enabled = 1
WHEN NOT MATCHED THEN INSERT (work_time_type_id, work_time_type_name, regular_start_minutes, regular_end_minutes, night_start_minutes, night_end_minutes, display_order, enabled)
VALUES (source.work_time_type_id, source.work_time_type_name, source.regular_start_minutes, source.regular_end_minutes, source.night_start_minutes, source.night_end_minutes, source.display_order, 1);

MERGE INTO work_time_types target
USING (SELECT 'WT002' work_time_type_id, '短時間勤務' work_time_type_name, 540 regular_start_minutes, 1050 regular_end_minutes, 1320 night_start_minutes, 300 night_end_minutes, 2 display_order FROM dual) source
ON (target.work_time_type_id = source.work_time_type_id)
WHEN MATCHED THEN UPDATE SET target.work_time_type_name = source.work_time_type_name, target.regular_start_minutes = source.regular_start_minutes, target.regular_end_minutes = source.regular_end_minutes, target.night_start_minutes = source.night_start_minutes, target.night_end_minutes = source.night_end_minutes, target.display_order = source.display_order, target.enabled = 1
WHEN NOT MATCHED THEN INSERT (work_time_type_id, work_time_type_name, regular_start_minutes, regular_end_minutes, night_start_minutes, night_end_minutes, display_order, enabled)
VALUES (source.work_time_type_id, source.work_time_type_name, source.regular_start_minutes, source.regular_end_minutes, source.night_start_minutes, source.night_end_minutes, source.display_order, 1);

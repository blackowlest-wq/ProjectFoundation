-- Master data seed for Oracle Database.
-- Run after schema-login.sql or schema-daily-report.sql.

MERGE INTO groups target
USING (SELECT 'G001' group_id, '第1開発グループ' group_name, 1 display_order FROM dual) source
ON (target.group_id = source.group_id)
WHEN MATCHED THEN UPDATE SET target.group_name = source.group_name, target.display_order = source.display_order, target.enabled = 1
WHEN NOT MATCHED THEN INSERT (group_id, group_name, display_order, enabled)
VALUES (source.group_id, source.group_name, source.display_order, 1);

MERGE INTO groups target
USING (SELECT 'G002' group_id, '第2開発グループ' group_name, 2 display_order FROM dual) source
ON (target.group_id = source.group_id)
WHEN MATCHED THEN UPDATE SET target.group_name = source.group_name, target.display_order = source.display_order, target.enabled = 1
WHEN NOT MATCHED THEN INSERT (group_id, group_name, display_order, enabled)
VALUES (source.group_id, source.group_name, source.display_order, 1);

MERGE INTO groups target
USING (SELECT 'G099' group_id, '他部署グループ' group_name, 99 display_order FROM dual) source
ON (target.group_id = source.group_id)
WHEN MATCHED THEN UPDATE SET target.group_name = source.group_name, target.display_order = source.display_order, target.enabled = 0
WHEN NOT MATCHED THEN INSERT (group_id, group_name, display_order, enabled)
VALUES (source.group_id, source.group_name, source.display_order, 0);

MERGE INTO groups target
USING (SELECT 'G900' group_id, '管理グループ' group_name, 900 display_order FROM dual) source
ON (target.group_id = source.group_id)
WHEN MATCHED THEN UPDATE SET target.group_name = source.group_name, target.display_order = source.display_order, target.enabled = 1
WHEN NOT MATCHED THEN INSERT (group_id, group_name, display_order, enabled)
VALUES (source.group_id, source.group_name, source.display_order, 1);

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

-- The application keeps message keys in source and display text in this catalog.
MERGE INTO message_catalog target
USING (SELECT 'security.authentication_required' message_key, 'ja-JP' locale, 'ログインが必要です。' message_text FROM dual) source
ON (target.message_key = source.message_key AND target.locale = source.locale)
WHEN MATCHED THEN UPDATE SET target.message_text = source.message_text, target.enabled = 1
WHEN NOT MATCHED THEN INSERT (message_key, locale, message_text, enabled)
VALUES (source.message_key, source.locale, source.message_text, 1);

MERGE INTO message_catalog target
USING (SELECT 'ui.catalog_unavailable' message_key, 'ja-JP' locale, 'メッセージ設定を読み込めませんでした。' message_text FROM dual) source
ON (target.message_key = source.message_key AND target.locale = source.locale)
WHEN MATCHED THEN UPDATE SET target.message_text = source.message_text, target.enabled = 1
WHEN NOT MATCHED THEN INSERT (message_key, locale, message_text, enabled)
VALUES (source.message_key, source.locale, source.message_text, 1);

MERGE INTO message_catalog target
USING (
    SELECT 'status.draft' message_key, 'ja-JP' locale, '未提出' message_text FROM dual
    UNION ALL SELECT 'status.draft_editor', 'ja-JP', '下書き' FROM dual
    UNION ALL SELECT 'status.pending', 'ja-JP', '承認待ち' FROM dual
    UNION ALL SELECT 'status.rejected', 'ja-JP', '差戻し' FROM dual
    UNION ALL SELECT 'status.approved', 'ja-JP', '承認済み' FROM dual
    UNION ALL SELECT 'ui.brand', 'ja-JP', '日報管理' FROM dual
    UNION ALL SELECT 'ui.page_title', 'ja-JP', '日報カレンダー・一覧' FROM dual
    UNION ALL SELECT 'ui.role.employee', 'ja-JP', '社員' FROM dual
    UNION ALL SELECT 'ui.role.manager', 'ja-JP', '上長' FROM dual
    UNION ALL SELECT 'ui.role.admin', 'ja-JP', '管理者' FROM dual
    UNION ALL SELECT 'ui.loading', 'ja-JP', '読み込み中...' FROM dual
    UNION ALL SELECT 'ui.searching', 'ja-JP', '検索中...' FROM dual
    UNION ALL SELECT 'ui.logout', 'ja-JP', 'ログアウト' FROM dual
    UNION ALL SELECT 'ui.logout_failed', 'ja-JP', 'ログアウトに失敗しました。時間をおいて再度お試しください。' FROM dual
    UNION ALL SELECT 'ui.login_required', 'ja-JP', 'ログインが必要です。' FROM dual
    UNION ALL SELECT 'ui.login_failed', 'ja-JP', 'ログインに失敗しました。' FROM dual
    UNION ALL SELECT 'error.daily_report_list', 'ja-JP', '日報一覧の取得に失敗しました。' FROM dual
    UNION ALL SELECT 'error.pending_approvals', 'ja-JP', '未承認一覧の取得に失敗しました。' FROM dual
    UNION ALL SELECT 'error.master_load', 'ja-JP', 'マスタデータの読み込みに失敗しました。' FROM dual
    UNION ALL SELECT 'error.daily_report_load', 'ja-JP', '日報の読み込みに失敗しました。' FROM dual
    UNION ALL SELECT 'error.save_failed', 'ja-JP', '保存に失敗しました。' FROM dual
    UNION ALL SELECT 'error.calculation_reload', 'ja-JP', '保存は完了しましたが、計算結果の再取得に失敗しました。' FROM dual
    UNION ALL SELECT 'error.master_not_ready', 'ja-JP', '案件と作業分類の読み込みが完了していません。' FROM dual
    UNION ALL SELECT 'success.saved', 'ja-JP', '保存しました。' FROM dual
    UNION ALL SELECT 'success.saved_and_submitted', 'ja-JP', '保存して提出しました。' FROM dual
    UNION ALL SELECT 'empty.no_reports', 'ja-JP', '該当する日報はありません。' FROM dual
    UNION ALL SELECT 'empty.no_pending_approvals', 'ja-JP', '承認待ちの日報はありません。' FROM dual
    UNION ALL SELECT 'form.read_only_status', 'ja-JP', 'この状態の日報は編集できません。' FROM dual
    UNION ALL SELECT 'validation.date_required', 'ja-JP', '日付を入力してください。' FROM dual
    UNION ALL SELECT 'validation.holiday_type_master_required', 'ja-JP', '休日区分マスタを読み込んでください。' FROM dual
    UNION ALL SELECT 'validation.paid_leave_forbidden', 'ja-JP', '有給休暇では勤務時刻と作業明細を入力できません。' FROM dual
    UNION ALL SELECT 'validation.work_inputs_required', 'ja-JP', '勤務時刻と1件以上の作業明細を入力してください。' FROM dual
    UNION ALL SELECT 'validation.reject_comment_required', 'ja-JP', '差し戻しコメントを入力してください。' FROM dual
    UNION ALL SELECT 'validation.reject_comment_max_length', 'ja-JP', '差し戻しコメントは1000文字以内で入力してください。' FROM dual
    UNION ALL SELECT 'validation.search_period_required', 'ja-JP', '対象期間を指定してください。' FROM dual
    UNION ALL SELECT 'validation.search_period_format', 'ja-JP', '対象期間の日付形式が正しくありません。' FROM dual
) source
ON (target.message_key = source.message_key AND target.locale = source.locale)
WHEN MATCHED THEN UPDATE SET target.message_text = source.message_text, target.enabled = 1
WHEN NOT MATCHED THEN INSERT (message_key, locale, message_text, enabled)
VALUES (source.message_key, source.locale, source.message_text, 1);

MERGE INTO message_catalog target
USING (SELECT 'security.access_denied' message_key, 'ja-JP' locale, '権限がありません。' message_text FROM dual) source
ON (target.message_key = source.message_key AND target.locale = source.locale)
WHEN MATCHED THEN UPDATE SET target.message_text = source.message_text, target.enabled = 1
WHEN NOT MATCHED THEN INSERT (message_key, locale, message_text, enabled)
VALUES (source.message_key, source.locale, source.message_text, 1);

MERGE INTO message_catalog target
USING (SELECT 'auth.invalid_credentials' message_key, 'ja-JP' locale, 'ログインIDまたはパスワードが正しくありません。' message_text FROM dual) source
ON (target.message_key = source.message_key AND target.locale = source.locale)
WHEN MATCHED THEN UPDATE SET target.message_text = source.message_text, target.enabled = 1
WHEN NOT MATCHED THEN INSERT (message_key, locale, message_text, enabled)
VALUES (source.message_key, source.locale, source.message_text, 1);

MERGE INTO message_catalog target
USING (SELECT 'validation.invalid' message_key, 'ja-JP' locale, '入力内容に誤りがあります。' message_text FROM dual) source
ON (target.message_key = source.message_key AND target.locale = source.locale)
WHEN MATCHED THEN UPDATE SET target.message_text = source.message_text, target.enabled = 1
WHEN NOT MATCHED THEN INSERT (message_key, locale, message_text, enabled)
VALUES (source.message_key, source.locale, source.message_text, 1);

MERGE INTO message_catalog target
USING (SELECT 'validation.invalid_format' message_key, 'ja-JP' locale, '形式が正しくありません。' message_text FROM dual) source
ON (target.message_key = source.message_key AND target.locale = source.locale)
WHEN MATCHED THEN UPDATE SET target.message_text = source.message_text, target.enabled = 1
WHEN NOT MATCHED THEN INSERT (message_key, locale, message_text, enabled)
VALUES (source.message_key, source.locale, source.message_text, 1);

MERGE INTO message_catalog target
USING (SELECT 'system.unexpected' message_key, 'ja-JP' locale, 'システムエラーが発生しました。' message_text FROM dual) source
ON (target.message_key = source.message_key AND target.locale = source.locale)
WHEN MATCHED THEN UPDATE SET target.message_text = source.message_text, target.enabled = 1
WHEN NOT MATCHED THEN INSERT (message_key, locale, message_text, enabled)
VALUES (source.message_key, source.locale, source.message_text, 1);

MERGE INTO message_catalog target
USING (SELECT 'business.conflict' message_key, 'ja-JP' locale, '業務処理を完了できません。' message_text FROM dual) source
ON (target.message_key = source.message_key AND target.locale = source.locale)
WHEN MATCHED THEN UPDATE SET target.message_text = source.message_text, target.enabled = 1
WHEN NOT MATCHED THEN INSERT (message_key, locale, message_text, enabled)
VALUES (source.message_key, source.locale, source.message_text, 1);

MERGE INTO message_catalog target
USING (
    SELECT 'auth.login_id.required' message_key, 'ja-JP' locale, 'ログインIDは必須です。' message_text FROM dual
    UNION ALL SELECT 'auth.login_id.max_length', 'ja-JP', 'ログインIDは80文字以内で入力してください。' FROM dual
    UNION ALL SELECT 'auth.login_id.invalid_format', 'ja-JP', 'ログインIDは半角英数字で入力してください。' FROM dual
    UNION ALL SELECT 'auth.password.required', 'ja-JP', 'パスワードは必須です。' FROM dual
    UNION ALL SELECT 'auth.password.max_length', 'ja-JP', 'パスワードは100文字以内で入力してください。' FROM dual
    UNION ALL SELECT 'auth.password.invalid_format', 'ja-JP', 'パスワードは半角英数字で入力してください。' FROM dual
    UNION ALL SELECT 'validation.holiday_type_required', 'ja-JP', '休日区分を選択してください。' FROM dual
    UNION ALL SELECT 'validation.holiday_type_not_found', 'ja-JP', '休日区分が存在しません。' FROM dual
    UNION ALL SELECT 'validation.break_type_not_found', 'ja-JP', '休憩区分が存在しません。' FROM dual
    UNION ALL SELECT 'validation.work_time_type_not_found', 'ja-JP', '勤務区分が存在しません。' FROM dual
    UNION ALL SELECT 'validation.paid_leave_work_time_forbidden', 'ja-JP', '有給休暇では勤務時刻を入力できません。' FROM dual
    UNION ALL SELECT 'validation.paid_leave_work_items_forbidden', 'ja-JP', '有給休暇では作業明細を入力できません。' FROM dual
    UNION ALL SELECT 'validation.holiday_work_time_forbidden', 'ja-JP', '休日で作業明細がない場合、勤務時刻は入力できません。' FROM dual
    UNION ALL SELECT 'validation.start_time_required', 'ja-JP', '勤務開始時刻を入力してください。' FROM dual
    UNION ALL SELECT 'validation.end_time_required', 'ja-JP', '勤務終了時刻を入力してください。' FROM dual
    UNION ALL SELECT 'validation.work_items_required', 'ja-JP', '作業明細を1件以上入力してください。' FROM dual
    UNION ALL SELECT 'validation.end_time_after_start', 'ja-JP', '勤務終了時刻は勤務開始時刻より後にしてください。' FROM dual
    UNION ALL SELECT 'validation.work_time_type_required', 'ja-JP', '利用者の勤務設定が未設定です。' FROM dual
    UNION ALL SELECT 'validation.break_minutes_less_than_work', 'ja-JP', '休憩時間は勤務時間未満になるように設定してください。' FROM dual
    UNION ALL SELECT 'validation.work_minutes_positive', 'ja-JP', '勤務時間は1分以上になるように入力してください。' FROM dual
    UNION ALL SELECT 'validation.work_items_minutes_match', 'ja-JP', '作業時間の合計は実勤務時間と一致させてください。' FROM dual
    UNION ALL SELECT 'validation.time_format', 'ja-JP', '時刻はHH:mm形式で入力してください。' FROM dual
    UNION ALL SELECT 'validation.project_not_found', 'ja-JP', '案件が存在しません。' FROM dual
    UNION ALL SELECT 'validation.work_category_not_found', 'ja-JP', '作業分類が存在しません。' FROM dual
    UNION ALL SELECT 'validation.work_item_minutes_positive', 'ja-JP', '作業時間は1分以上で入力してください。' FROM dual
    UNION ALL SELECT 'validation.date_from_required', 'ja-JP', '検索開始日を指定してください。' FROM dual
    UNION ALL SELECT 'validation.date_to_required', 'ja-JP', '検索終了日を指定してください。' FROM dual
    UNION ALL SELECT 'validation.date_to_before_date_from', 'ja-JP', '検索終了日は検索開始日以降にしてください。' FROM dual
    UNION ALL SELECT 'validation.date_range_too_long', 'ja-JP', '検索対象期間は366日以内で指定してください。' FROM dual
    UNION ALL SELECT 'validation.stored_paid_leave_invalid', 'ja-JP', '有給休暇では勤務時刻と作業明細を入力できません。' FROM dual
    UNION ALL SELECT 'validation.stored_work_time_required', 'ja-JP', '勤務時刻を入力してください。' FROM dual
    UNION ALL SELECT 'validation.stored_break_minutes_mismatch', 'ja-JP', '保存済みの休憩時間が勤務設定と一致しません。' FROM dual
    UNION ALL SELECT 'validation.stored_work_minutes_mismatch', 'ja-JP', '保存済みの勤務時間が勤務設定と一致しません。' FROM dual
    UNION ALL SELECT 'validation.stored_work_item_minutes_mismatch', 'ja-JP', '保存済みの勤務時間内訳が勤務設定と一致しません。' FROM dual
    UNION ALL SELECT 'report.not_found', 'ja-JP', 'Daily report was not found.' FROM dual
    UNION ALL SELECT 'report.forbidden', 'ja-JP', 'Access is forbidden.' FROM dual
    UNION ALL SELECT 'report.duplicate', 'ja-JP', 'Daily report already exists.' FROM dual
    UNION ALL SELECT 'report.invalid_status', 'ja-JP', 'Daily report cannot be edited in the current status.' FROM dual
    UNION ALL SELECT 'report.only_employees', 'ja-JP', 'Only employees can use this operation.' FROM dual
    UNION ALL SELECT 'report.only_managers', 'ja-JP', 'Only managers can use this operation.' FROM dual
    UNION ALL SELECT 'report.submit_draft_only', 'ja-JP', 'Only draft reports can be submitted.' FROM dual
    UNION ALL SELECT 'report.resubmit_rejected_only', 'ja-JP', 'Only rejected reports can be resubmitted.' FROM dual
    UNION ALL SELECT 'report.approve_pending_only', 'ja-JP', 'Only pending reports can be processed.' FROM dual
) source
ON (target.message_key = source.message_key AND target.locale = source.locale)
WHEN MATCHED THEN UPDATE SET target.message_text = source.message_text, target.enabled = 1
WHEN NOT MATCHED THEN INSERT (message_key, locale, message_text, enabled)
VALUES (source.message_key, source.locale, source.message_text, 1);

MERGE INTO work_time_types target
USING (SELECT 'WT002' work_time_type_id, '短時間勤務' work_time_type_name, 540 regular_start_minutes, 1050 regular_end_minutes, 1320 night_start_minutes, 300 night_end_minutes, 2 display_order FROM dual) source
ON (target.work_time_type_id = source.work_time_type_id)
WHEN MATCHED THEN UPDATE SET target.work_time_type_name = source.work_time_type_name, target.regular_start_minutes = source.regular_start_minutes, target.regular_end_minutes = source.regular_end_minutes, target.night_start_minutes = source.night_start_minutes, target.night_end_minutes = source.night_end_minutes, target.display_order = source.display_order, target.enabled = 1
WHEN NOT MATCHED THEN INSERT (work_time_type_id, work_time_type_name, regular_start_minutes, regular_end_minutes, night_start_minutes, night_end_minutes, display_order, enabled)
VALUES (source.work_time_type_id, source.work_time_type_name, source.regular_start_minutes, source.regular_end_minutes, source.night_start_minutes, source.night_end_minutes, source.display_order, 1);

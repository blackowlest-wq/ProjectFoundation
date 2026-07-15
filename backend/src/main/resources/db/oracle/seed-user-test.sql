-- Confirmation user seed for Oracle Database.
-- Connect as the application schema user before running this script.
-- Login ID: employee901
-- Password: password

SET DEFINE OFF

MERGE INTO users target
USING (
    SELECT
        'U901' AS user_id,
        'E901' AS employee_id,
        'employee901' AS login_id,
        '$2a$10$NTS.B70pC4gg017cKYh/xuY/RQk6w2FTUswp9YTxKDUtuIYkRwRuS' AS password_hash,
        '確認用 社員' AS user_name,
        'EMPLOYEE' AS user_role,
        'G001' AS group_id,
        '第1開発グループ' AS group_name,
        'BT001' AS break_type_id,
        '標準休憩' AS break_type_name,
        'WT001' AS work_time_type_id,
        '通常勤務' AS work_time_type_name
    FROM dual
) source
ON (target.user_id = source.user_id)
WHEN MATCHED THEN
    UPDATE SET
        target.employee_id = source.employee_id,
        target.login_id = source.login_id,
        target.password_hash = source.password_hash,
        target.user_name = source.user_name,
        target.user_role = source.user_role,
        target.group_id = source.group_id,
        target.group_name = source.group_name,
        target.break_type_id = source.break_type_id,
        target.break_type_name = source.break_type_name,
        target.work_time_type_id = source.work_time_type_id,
        target.work_time_type_name = source.work_time_type_name,
        target.updated_at = SYSTIMESTAMP
WHEN NOT MATCHED THEN
    INSERT (
        user_id,
        employee_id,
        login_id,
        password_hash,
        user_name,
        user_role,
        group_id,
        group_name,
        break_type_id,
        break_type_name,
        work_time_type_id,
        work_time_type_name
    )
    VALUES (
        source.user_id,
        source.employee_id,
        source.login_id,
        source.password_hash,
        source.user_name,
        source.user_role,
        source.group_id,
        source.group_name,
        source.break_type_id,
        source.break_type_name,
        source.work_time_type_id,
        source.work_time_type_name
    );

COMMIT;

SELECT user_id, employee_id, login_id, user_name, user_role, group_id, break_type_id, work_time_type_id
FROM users
WHERE login_id = 'employee901';

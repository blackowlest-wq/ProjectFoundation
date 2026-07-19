-- Daily report schema extension for Oracle Database.
-- Connect as the application schema user after users table is created.

CREATE TABLE projects (
    project_id VARCHAR2(20 CHAR) NOT NULL,
    project_name VARCHAR2(120 CHAR) NOT NULL,
    display_order NUMBER(5) NOT NULL,
    enabled NUMBER(1) DEFAULT 1 NOT NULL,
    CONSTRAINT pk_projects PRIMARY KEY (project_id)
);

CREATE TABLE work_categories (
    work_category_id VARCHAR2(20 CHAR) NOT NULL,
    work_category_name VARCHAR2(120 CHAR) NOT NULL,
    display_order NUMBER(5) NOT NULL,
    enabled NUMBER(1) DEFAULT 1 NOT NULL,
    CONSTRAINT pk_work_categories PRIMARY KEY (work_category_id)
);

CREATE TABLE holiday_types (
    holiday_type VARCHAR2(20 CHAR) NOT NULL,
    holiday_type_name VARCHAR2(120 CHAR) NOT NULL,
    requires_work_time NUMBER(1) NOT NULL,
    allows_work_items NUMBER(1) NOT NULL,
    display_order NUMBER(5) NOT NULL,
    enabled NUMBER(1) DEFAULT 1 NOT NULL,
    CONSTRAINT pk_holiday_types PRIMARY KEY (holiday_type)
);

CREATE TABLE break_types (
    break_type_id VARCHAR2(20 CHAR) NOT NULL,
    break_type_name VARCHAR2(120 CHAR) NOT NULL,
    display_order NUMBER(5) NOT NULL,
    enabled NUMBER(1) DEFAULT 1 NOT NULL,
    CONSTRAINT pk_break_types PRIMARY KEY (break_type_id)
);

CREATE TABLE break_type_periods (
    break_type_id VARCHAR2(20 CHAR) NOT NULL,
    start_minutes NUMBER(4) NOT NULL,
    end_minutes NUMBER(4) NOT NULL,
    display_order NUMBER(5) NOT NULL,
    CONSTRAINT fk_break_type_periods_type FOREIGN KEY (break_type_id) REFERENCES break_types(break_type_id)
);

CREATE TABLE work_time_types (
    work_time_type_id VARCHAR2(20 CHAR) NOT NULL,
    work_time_type_name VARCHAR2(120 CHAR) NOT NULL,
    regular_start_minutes NUMBER(4) NOT NULL,
    regular_end_minutes NUMBER(4) NOT NULL,
    night_start_minutes NUMBER(4) NOT NULL,
    night_end_minutes NUMBER(4) NOT NULL,
    display_order NUMBER(5) NOT NULL,
    enabled NUMBER(1) DEFAULT 1 NOT NULL,
    CONSTRAINT pk_work_time_types PRIMARY KEY (work_time_type_id)
);

CREATE TABLE daily_reports (
    report_id VARCHAR2(40 CHAR) NOT NULL,
    employee_user_id VARCHAR2(20 CHAR) NOT NULL,
    employee_id VARCHAR2(20 CHAR) NOT NULL,
    employee_name VARCHAR2(120 CHAR) NOT NULL,
    group_id VARCHAR2(20 CHAR) NOT NULL,
    group_name VARCHAR2(120 CHAR) NOT NULL,
    report_date DATE NOT NULL,
    holiday_type VARCHAR2(20 CHAR) NOT NULL,
    break_type_id VARCHAR2(20 CHAR),
    break_type_name VARCHAR2(120 CHAR),
    work_time_type_id VARCHAR2(20 CHAR),
    work_time_type_name VARCHAR2(120 CHAR),
    start_time_minutes NUMBER(4),
    end_time_minutes NUMBER(4),
    break_minutes NUMBER(5),
    work_minutes NUMBER(5),
    regular_work_minutes NUMBER(5),
    overtime_work_minutes NUMBER(5),
    night_work_minutes NUMBER(5),
    remarks VARCHAR2(1000 CHAR),
    approval_status VARCHAR2(20 CHAR) NOT NULL,
    submitted_at TIMESTAMP WITH LOCAL TIME ZONE,
    approver_user_id VARCHAR2(20 CHAR),
    approver_name VARCHAR2(120 CHAR),
    approved_at TIMESTAMP WITH LOCAL TIME ZONE,
    rejector_user_id VARCHAR2(20 CHAR),
    rejector_name VARCHAR2(120 CHAR),
    rejected_at TIMESTAMP WITH LOCAL TIME ZONE,
    reject_comment VARCHAR2(1000 CHAR),
    CONSTRAINT pk_daily_reports PRIMARY KEY (report_id),
    CONSTRAINT fk_daily_reports_employee FOREIGN KEY (employee_user_id) REFERENCES users(user_id),
    CONSTRAINT uq_daily_reports_employee_date UNIQUE (employee_user_id, report_date),
    CONSTRAINT fk_daily_reports_holiday_type FOREIGN KEY (holiday_type) REFERENCES holiday_types(holiday_type),
    CONSTRAINT fk_daily_reports_break_type FOREIGN KEY (break_type_id) REFERENCES break_types(break_type_id),
    CONSTRAINT fk_daily_reports_work_time_type FOREIGN KEY (work_time_type_id) REFERENCES work_time_types(work_time_type_id),
    CONSTRAINT ck_daily_reports_status CHECK (approval_status IN ('DRAFT', 'PENDING', 'REJECTED', 'APPROVED')),
    CONSTRAINT ck_daily_reports_time_order CHECK (
        start_time_minutes IS NULL OR end_time_minutes IS NULL OR end_time_minutes > start_time_minutes
    )
);

CREATE INDEX ix_daily_reports_calendar ON daily_reports(report_date, employee_user_id, group_id, approval_status, holiday_type);

CREATE TABLE daily_report_work_items (
    work_item_id VARCHAR2(40 CHAR) NOT NULL,
    report_id VARCHAR2(40 CHAR) NOT NULL,
    project_id VARCHAR2(20 CHAR) NOT NULL,
    work_category_id VARCHAR2(20 CHAR) NOT NULL,
    work_minutes NUMBER(5) NOT NULL,
    display_order NUMBER(5) NOT NULL,
    CONSTRAINT pk_daily_report_work_items PRIMARY KEY (work_item_id),
    CONSTRAINT fk_daily_report_items_report FOREIGN KEY (report_id) REFERENCES daily_reports(report_id),
    CONSTRAINT fk_daily_report_items_project FOREIGN KEY (project_id) REFERENCES projects(project_id),
    CONSTRAINT fk_daily_report_items_category FOREIGN KEY (work_category_id) REFERENCES work_categories(work_category_id),
    CONSTRAINT ck_daily_report_items_minutes CHECK (work_minutes >= 1)
);

CREATE INDEX ix_daily_report_items_report ON daily_report_work_items(report_id);

CREATE TABLE manager_group_permissions (
    manager_user_id VARCHAR2(20 CHAR) NOT NULL,
    group_id VARCHAR2(20 CHAR) NOT NULL,
    CONSTRAINT pk_manager_group_permissions PRIMARY KEY (manager_user_id, group_id),
    CONSTRAINT fk_manager_group_permissions_user FOREIGN KEY (manager_user_id) REFERENCES users(user_id)
);

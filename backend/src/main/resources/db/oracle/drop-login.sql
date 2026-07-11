-- Drop login feature schema for Oracle Database.
-- Connect as DAILY_REPORT_TEST before running this script.

DROP TABLE daily_report_work_items CASCADE CONSTRAINTS;
DROP TABLE daily_reports CASCADE CONSTRAINTS;
DROP TABLE users CASCADE CONSTRAINTS;

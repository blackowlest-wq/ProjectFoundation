/**
 * ローカル確認・テスト用のDDL補助と初期データ投入を行うクラス。
 * 本番マイグレーションではなく、開発研究プロジェクトでOracle実機テストを再現しやすくするための初期化処理。
 */
package com.example.dailyreport.config;

import com.example.dailyreport.auth.AppUser;
import com.example.dailyreport.auth.Role;
import com.example.dailyreport.auth.UserRepository;
import java.sql.SQLException;
import org.springframework.boot.CommandLineRunner;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;
import org.springframework.dao.DataAccessException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.crypto.password.PasswordEncoder;

@Configuration
@Profile({"test", "oracle-test"})
public class DataInitializer {
    @Bean
    CommandLineRunner seedUsers(UserRepository userRepository, PasswordEncoder passwordEncoder, JdbcTemplate jdbcTemplate) {
        return args -> {
            createMasterTablesIfNeeded(jdbcTemplate);
            createPermissionTablesIfNeeded(jdbcTemplate);
            seedMasterData(jdbcTemplate);
            if (userRepository.count() == 0) {
                userRepository.save(employee(passwordEncoder));
                userRepository.save(manager(passwordEncoder));
                userRepository.save(admin(passwordEncoder));
            }
            seedManagerPermissions(jdbcTemplate);
        };
    }

    private void createMasterTablesIfNeeded(JdbcTemplate jdbcTemplate) {
        // 既存Oracle環境へ繰り返し起動できるよう、CREATE TABLEは存在済みエラーだけ無視する。
        executeIgnoringAlreadyExists(jdbcTemplate, """
                CREATE TABLE projects (
                    project_id VARCHAR2(20 CHAR) NOT NULL,
                    project_name VARCHAR2(120 CHAR) NOT NULL,
                    display_order NUMBER(5) NOT NULL,
                    enabled NUMBER(1) DEFAULT 1 NOT NULL,
                    CONSTRAINT pk_projects PRIMARY KEY (project_id)
                )
                """);
        executeIgnoringAlreadyExists(jdbcTemplate, """
                CREATE TABLE work_categories (
                    work_category_id VARCHAR2(20 CHAR) NOT NULL,
                    work_category_name VARCHAR2(120 CHAR) NOT NULL,
                    display_order NUMBER(5) NOT NULL,
                    enabled NUMBER(1) DEFAULT 1 NOT NULL,
                    CONSTRAINT pk_work_categories PRIMARY KEY (work_category_id)
                )
                """);
        executeIgnoringAlreadyExists(jdbcTemplate, """
                CREATE TABLE holiday_types (
                    holiday_type VARCHAR2(20 CHAR) NOT NULL,
                    holiday_type_name VARCHAR2(120 CHAR) NOT NULL,
                    requires_work_time NUMBER(1) NOT NULL,
                    allows_work_items NUMBER(1) NOT NULL,
                    display_order NUMBER(5) NOT NULL,
                    enabled NUMBER(1) DEFAULT 1 NOT NULL,
                    CONSTRAINT pk_holiday_types PRIMARY KEY (holiday_type)
                )
                """);
        executeIgnoringAlreadyExists(jdbcTemplate, """
                CREATE TABLE break_types (
                    break_type_id VARCHAR2(20 CHAR) NOT NULL,
                    break_type_name VARCHAR2(120 CHAR) NOT NULL,
                    display_order NUMBER(5) NOT NULL,
                    enabled NUMBER(1) DEFAULT 1 NOT NULL,
                    CONSTRAINT pk_break_types PRIMARY KEY (break_type_id)
                )
                """);
        executeIgnoringAlreadyExists(jdbcTemplate, """
                CREATE TABLE break_type_periods (
                    break_type_id VARCHAR2(20 CHAR) NOT NULL,
                    start_minutes NUMBER(4) NOT NULL,
                    end_minutes NUMBER(4) NOT NULL,
                    display_order NUMBER(5) NOT NULL,
                    CONSTRAINT fk_break_type_periods_type FOREIGN KEY (break_type_id) REFERENCES break_types(break_type_id)
                )
                """);
        executeIgnoringAlreadyExists(jdbcTemplate, """
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
                )
                """);
    }

    private void createPermissionTablesIfNeeded(JdbcTemplate jdbcTemplate) {
        executeIgnoringAlreadyExists(jdbcTemplate, """
                CREATE TABLE manager_group_permissions (
                    manager_user_id VARCHAR2(20 CHAR) NOT NULL,
                    group_id VARCHAR2(20 CHAR) NOT NULL,
                    CONSTRAINT pk_manager_group_permissions PRIMARY KEY (manager_user_id, group_id),
                    CONSTRAINT fk_manager_group_permissions_user FOREIGN KEY (manager_user_id) REFERENCES users(user_id)
                )
                """);
    }

    private void executeIgnoringAlreadyExists(JdbcTemplate jdbcTemplate, String sql) {
        try {
            jdbcTemplate.execute(sql);
        } catch (DataAccessException exception) {
            if (!isAlreadyExists(exception)) {
                throw exception;
            }
        }
    }

    private boolean isAlreadyExists(Throwable exception) {
        Throwable current = exception;
        while (current != null) {
            if (current instanceof SQLException sqlException && sqlException.getErrorCode() == 955) {
                // ORA-00955: name is already used by an existing object
                return true;
            }
            String message = current.getMessage();
            if (message != null && message.contains("ORA-00955")) {
                return true;
            }
            current = current.getCause();
        }
        return false;
    }

    private void seedMasterData(JdbcTemplate jdbcTemplate) {
        // マスタはMERGEで投入し、名称変更や表示順変更をテスト環境へ反映しやすくする。
        mergeProject(jdbcTemplate, "P001", "プロジェクトA", 1);
        mergeProject(jdbcTemplate, "P002", "プロジェクトB", 2);
        mergeWorkCategory(jdbcTemplate, "WC001", "設計", 1);
        mergeWorkCategory(jdbcTemplate, "WC002", "実装", 2);
        mergeWorkCategory(jdbcTemplate, "WC003", "テスト", 3);
        mergeHolidayType(jdbcTemplate, "WORKDAY", "通常勤務", 1, 1, 1);
        mergeHolidayType(jdbcTemplate, "HOLIDAY", "休日", 0, 1, 2);
        mergeHolidayType(jdbcTemplate, "PAID_LEAVE", "有給休暇", 0, 0, 3);
        mergeHolidayType(jdbcTemplate, "AM_OFF", "午前休", 1, 1, 4);
        mergeHolidayType(jdbcTemplate, "PM_OFF", "午後休", 1, 1, 5);
        mergeBreakType(jdbcTemplate, "BT001", "標準休憩", 1);
        mergeBreakType(jdbcTemplate, "BT002", "分割休憩", 2);
        // 休憩時間帯は複数行で構成されるため、既存行を消してから現在定義を入れ直す。
        deleteBreakPeriods(jdbcTemplate, "BT001");
        insertBreakPeriod(jdbcTemplate, "BT001", 720, 780, 1);
        deleteBreakPeriods(jdbcTemplate, "BT002");
        insertBreakPeriod(jdbcTemplate, "BT002", 720, 780, 1);
        insertBreakPeriod(jdbcTemplate, "BT002", 1050, 1065, 2);
        mergeWorkTimeType(jdbcTemplate, "WT001", "通常勤務", 540, 1080, 1320, 300, 1);
        mergeWorkTimeType(jdbcTemplate, "WT002", "短時間勤務", 540, 1050, 1320, 300, 2);
    }

    private void seedManagerPermissions(JdbcTemplate jdbcTemplate) {
        jdbcTemplate.update("""
                MERGE INTO manager_group_permissions target
                USING (SELECT 'U002' manager_user_id, 'G001' group_id FROM dual) source
                ON (target.manager_user_id = source.manager_user_id AND target.group_id = source.group_id)
                WHEN NOT MATCHED THEN INSERT (manager_user_id, group_id)
                VALUES (source.manager_user_id, source.group_id)
                """);
    }

    private void mergeProject(JdbcTemplate jdbcTemplate, String id, String name, int order) {
        jdbcTemplate.update("""
                MERGE INTO projects target
                USING (SELECT ? project_id, ? project_name, ? display_order FROM dual) source
                ON (target.project_id = source.project_id)
                WHEN MATCHED THEN UPDATE SET target.project_name = source.project_name, target.display_order = source.display_order, target.enabled = 1
                WHEN NOT MATCHED THEN INSERT (project_id, project_name, display_order, enabled)
                VALUES (source.project_id, source.project_name, source.display_order, 1)
                """, id, name, order);
    }

    private void mergeWorkCategory(JdbcTemplate jdbcTemplate, String id, String name, int order) {
        jdbcTemplate.update("""
                MERGE INTO work_categories target
                USING (SELECT ? work_category_id, ? work_category_name, ? display_order FROM dual) source
                ON (target.work_category_id = source.work_category_id)
                WHEN MATCHED THEN UPDATE SET target.work_category_name = source.work_category_name, target.display_order = source.display_order, target.enabled = 1
                WHEN NOT MATCHED THEN INSERT (work_category_id, work_category_name, display_order, enabled)
                VALUES (source.work_category_id, source.work_category_name, source.display_order, 1)
                """, id, name, order);
    }

    private void mergeHolidayType(JdbcTemplate jdbcTemplate, String id, String name, int requiresWorkTime,
                                  int allowsWorkItems, int order) {
        // requires_work_time / allows_work_items は、日報入力ルールの分岐をDBマスタ側で表す。
        jdbcTemplate.update("""
                MERGE INTO holiday_types target
                USING (SELECT ? holiday_type, ? holiday_type_name, ? requires_work_time, ? allows_work_items, ? display_order FROM dual) source
                ON (target.holiday_type = source.holiday_type)
                WHEN MATCHED THEN UPDATE SET target.holiday_type_name = source.holiday_type_name,
                    target.requires_work_time = source.requires_work_time, target.allows_work_items = source.allows_work_items,
                    target.display_order = source.display_order, target.enabled = 1
                WHEN NOT MATCHED THEN INSERT (holiday_type, holiday_type_name, requires_work_time, allows_work_items, display_order, enabled)
                VALUES (source.holiday_type, source.holiday_type_name, source.requires_work_time, source.allows_work_items, source.display_order, 1)
                """, id, name, requiresWorkTime, allowsWorkItems, order);
    }

    private void mergeBreakType(JdbcTemplate jdbcTemplate, String id, String name, int order) {
        jdbcTemplate.update("""
                MERGE INTO break_types target
                USING (SELECT ? break_type_id, ? break_type_name, ? display_order FROM dual) source
                ON (target.break_type_id = source.break_type_id)
                WHEN MATCHED THEN UPDATE SET target.break_type_name = source.break_type_name, target.display_order = source.display_order, target.enabled = 1
                WHEN NOT MATCHED THEN INSERT (break_type_id, break_type_name, display_order, enabled)
                VALUES (source.break_type_id, source.break_type_name, source.display_order, 1)
                """, id, name, order);
    }

    private void deleteBreakPeriods(JdbcTemplate jdbcTemplate, String breakTypeId) {
        jdbcTemplate.update("DELETE FROM break_type_periods WHERE break_type_id = ?", breakTypeId);
    }

    private void insertBreakPeriod(JdbcTemplate jdbcTemplate, String breakTypeId, int start, int end, int order) {
        jdbcTemplate.update("""
                INSERT INTO break_type_periods (break_type_id, start_minutes, end_minutes, display_order)
                VALUES (?, ?, ?, ?)
                """, breakTypeId, start, end, order);
    }

    private void mergeWorkTimeType(JdbcTemplate jdbcTemplate, String id, String name, int regularStart, int regularEnd,
                                   int nightStart, int nightEnd, int order) {
        // 勤務区分は通常時間帯と深夜時間帯を分で持ち、TimeRulesが内訳計算に利用する。
        jdbcTemplate.update("""
                MERGE INTO work_time_types target
                USING (SELECT ? work_time_type_id, ? work_time_type_name, ? regular_start_minutes, ? regular_end_minutes,
                              ? night_start_minutes, ? night_end_minutes, ? display_order FROM dual) source
                ON (target.work_time_type_id = source.work_time_type_id)
                WHEN MATCHED THEN UPDATE SET target.work_time_type_name = source.work_time_type_name,
                    target.regular_start_minutes = source.regular_start_minutes, target.regular_end_minutes = source.regular_end_minutes,
                    target.night_start_minutes = source.night_start_minutes, target.night_end_minutes = source.night_end_minutes,
                    target.display_order = source.display_order, target.enabled = 1
                WHEN NOT MATCHED THEN INSERT (work_time_type_id, work_time_type_name, regular_start_minutes, regular_end_minutes,
                    night_start_minutes, night_end_minutes, display_order, enabled)
                VALUES (source.work_time_type_id, source.work_time_type_name, source.regular_start_minutes, source.regular_end_minutes,
                    source.night_start_minutes, source.night_end_minutes, source.display_order, 1)
                """, id, name, regularStart, regularEnd, nightStart, nightEnd, order);
    }

    private AppUser employee(PasswordEncoder passwordEncoder) {
        return new AppUser("U001", "E001", "employee001", passwordEncoder.encode("password"),
                "山田 太郎", Role.EMPLOYEE, "G001", "第1開発グループ",
                "BT001", "標準休憩", "WT001", "通常勤務");
    }

    private AppUser manager(PasswordEncoder passwordEncoder) {
        return new AppUser("U002", "M001", "manager001", passwordEncoder.encode("password"),
                "佐藤 花子", Role.MANAGER, "G900", "管理グループ",
                null, null, null, null);
    }

    private AppUser admin(PasswordEncoder passwordEncoder) {
        return new AppUser("U003", "A001", "admin001", passwordEncoder.encode("password"),
                "鈴木 一郎", Role.ADMIN, null, null, null, null, null, null);
    }
}

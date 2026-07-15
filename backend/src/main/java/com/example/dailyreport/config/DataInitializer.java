/**
 * ローカル確認・テスト用のDDL補助と初期データ投入を行うクラス。
 * 本番マイグレーションではなく、開発研究プロジェクトでOracle実機テストを再現しやすくするための初期化処理。
 */
package com.example.dailyreport.config;

import com.example.dailyreport.auth.AppUser;
import com.example.dailyreport.auth.Role;
import com.example.dailyreport.auth.UserRepository;
import java.sql.SQLException;
import java.util.Map;
import org.springframework.beans.factory.annotation.Value;
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
    private final boolean allowDdl;

    DataInitializer(
            @Value("${DAILY_REPORT_ALLOW_DDL:false}") boolean allowDdl,
            @Value("${DAILY_REPORT_DDL_CLI_APPROVED:false}") boolean cliDdlApproved) {
        this.allowDdl = allowDdl && cliDdlApproved;
    }

    @Bean
    /**
     * Oracleの開発・テスト環境向けに、必要な表・マスタ・利用者・上長権限を依存順で初期化するRunnerを返す。
     */
    CommandLineRunner seedUsers(UserRepository userRepository, PasswordEncoder passwordEncoder, JdbcTemplate jdbcTemplate) {
        return args -> {
            // How: DDL・seedより先にOracleの論理識別値を確認し、誤接続先への副作用を防ぐ。
            verifyExpectedDatabase(jdbcTemplate);
            // How: DDL許可が有効な場合だけマスタ表・権限表を作成し、通常の実DBテストは既存スキーマを使う。
            // Why not: Oracle実DBテストでDDLを常時実行すると共有スキーマを破壊するため、設定と入口の二重許可に限定する。
            if (allowDdl) {
                createMasterTablesIfNeeded(jdbcTemplate);
                createPermissionTablesIfNeeded(jdbcTemplate);
            }
            seedMasterData(jdbcTemplate);
            // How: 利用者表の件数に依存せず、不足している標準テスト利用者だけを追加し、既存利用者を上書きしない。
            saveIfAbsent(userRepository, employee(passwordEncoder));
            saveIfAbsent(userRepository, manager(passwordEncoder));
            saveIfAbsent(userRepository, admin(passwordEncoder));
            seedManagerPermissions(jdbcTemplate);
        };
    }

    /**
     * 同じ利用者IDまたはログインIDが存在しない場合だけ、標準テスト利用者を追加する。
     */
    private void saveIfAbsent(UserRepository userRepository, AppUser user) {
        if (!userRepository.existsById(user.getUserId()) && userRepository.findByLoginId(user.getLoginId()).isEmpty()) {
            userRepository.save(user);
        }
    }

    /**
     * 接続後に確認したOracleのDB名、サービス名、セッションユーザーを期待値と照合する。
     */
    private void verifyExpectedDatabase(JdbcTemplate jdbcTemplate) {
        String expectedName = requiredEnvironment("DAILY_REPORT_DB_EXPECTED_NAME");
        String expectedService = requiredEnvironment("DAILY_REPORT_DB_EXPECTED_SERVICE");
        String expectedUser = requiredEnvironment("DAILY_REPORT_DB_EXPECTED_USER");
        Map<String, Object> identity = jdbcTemplate.queryForMap("""
                SELECT
                    SYS_CONTEXT('USERENV', 'DB_NAME') AS DB_NAME,
                    SYS_CONTEXT('USERENV', 'SERVICE_NAME') AS SERVICE_NAME,
                    SYS_CONTEXT('USERENV', 'SESSION_USER') AS SESSION_USER
                FROM dual
                """);
        assertIdentity(expectedName, identity.get("DB_NAME"), "DB_NAME");
        assertIdentity(expectedService, identity.get("SERVICE_NAME"), "SERVICE_NAME");
        assertIdentity(expectedUser, identity.get("SESSION_USER"), "SESSION_USER");
    }

    /**
     * Oracle接続先の識別に必要な環境変数が設定されていることを確認する。
     */
    private String requiredEnvironment(String name) {
        String value = System.getenv(name);
        if (value == null || value.isBlank()) {
            throw new IllegalStateException("Required Oracle identity environment variable is missing: " + name);
        }
        return value;
    }

    /**
     * Oracleから返された識別値を大小文字を区別せず期待値と照合する。
     */
    private void assertIdentity(String expected, Object actual, String field) {
        if (!expected.equalsIgnoreCase(String.valueOf(actual))) {
            throw new IllegalStateException("Oracle test identity mismatch: " + field);
        }
    }

    /**
     * 日報入力に必要なマスタ表を、既存表を壊さず必要時だけ作成する。
     */
    private void createMasterTablesIfNeeded(JdbcTemplate jdbcTemplate) {
        // Why not: 既存Oracle環境で再実行可能にしつつ、存在済み以外のDDLエラーは見逃さないため、ORA-00955だけを無視する。
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

    /**
     * 上長のグループ参照権限を保持する表を、既存表を壊さず作成する。
     */
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

    /**
     * DDLを実行し、既存オブジェクトを示す例外だけを再実行可能な結果として扱う。
     */
    private void executeIgnoringAlreadyExists(JdbcTemplate jdbcTemplate, String sql) {
        try {
            jdbcTemplate.execute(sql);
        } catch (DataAccessException exception) {
            // How: 既存オブジェクトの例外だけを処理済みとして終了し、それ以外のDDLエラーは再送出する。
            if (!isAlreadyExists(exception)) {
                throw exception;
            }
        }
    }

    /**
     * 例外チェーンをたどり、Oracleの既存オブジェクトエラーに該当するかを判定する。
     */
    private boolean isAlreadyExists(Throwable exception) {
        Throwable current = exception;
        while (current != null) {
            // How: SQLExceptionのエラーコード955を検出したら、例外チェーンの探索を終了する。
            if (current instanceof SQLException sqlException && sqlException.getErrorCode() == 955) {
                // Why not: 他のOracle例外を無視せず、既存オブジェクトを表すORA-00955だけを再実行可能として扱う。
                return true;
            }
            String message = current.getMessage();
            // How: JDBCドライバがエラーコードを保持しない場合は、メッセージのORA-00955表記で同じ判定を行う。
            if (message != null && message.contains("ORA-00955")) {
                return true;
            }
            current = current.getCause();
        }
        return false;
    }

    /**
     * 案件、作業分類、休日、休憩、勤務時間帯のマスタをMERGEで同期する。
     */
    private void seedMasterData(JdbcTemplate jdbcTemplate) {
        // Why not: INSERTだけにすると既存テスト環境の名称・表示順を更新できないため、マスタはMERGEで同期する。
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
        // Why not: 既存行へ追記すると古い休憩帯が残るため、複数行の定義を一度削除して現在定義へ置き換える。
        deleteBreakPeriods(jdbcTemplate, "BT001");
        insertBreakPeriod(jdbcTemplate, "BT001", 720, 780, 1);
        deleteBreakPeriods(jdbcTemplate, "BT002");
        insertBreakPeriod(jdbcTemplate, "BT002", 720, 780, 1);
        insertBreakPeriod(jdbcTemplate, "BT002", 1050, 1065, 2);
        mergeWorkTimeType(jdbcTemplate, "WT001", "通常勤務", 540, 1080, 1320, 300, 1);
        mergeWorkTimeType(jdbcTemplate, "WT002", "短時間勤務", 540, 1050, 1320, 300, 2);
    }

    /**
     * テスト用上長にグループ参照権限を登録し、既存登録時は何もしない。
     */
    private void seedManagerPermissions(JdbcTemplate jdbcTemplate) {
        jdbcTemplate.update("""
                MERGE INTO manager_group_permissions target
                USING (SELECT 'U002' manager_user_id, 'G001' group_id FROM dual) source
                ON (target.manager_user_id = source.manager_user_id AND target.group_id = source.group_id)
                WHEN NOT MATCHED THEN INSERT (manager_user_id, group_id)
                VALUES (source.manager_user_id, source.group_id)
                """);
    }

    /**
     * 案件マスタをID単位で追加または更新する。
     */
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

    /**
     * 作業分類マスタをID単位で追加または更新する。
     */
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

    /**
     * 休日区分と、その区分が許可する入力条件をDBマスタへ同期する。
     */
    private void mergeHolidayType(JdbcTemplate jdbcTemplate, String id, String name, int requiresWorkTime,
                                  int allowsWorkItems, int order) {
        // Why not: 日報入力ルールをJavaの固定分岐だけで管理するとマスタ変更と乖離するため、requires_work_time / allows_work_itemsでDB側に表す。
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

    /**
     * 休憩区分マスタをID単位で追加または更新する。
     */
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

    /**
     * 指定した休憩区分の既存休憩帯を全削除し、現在の定義へ置き換えられる状態にする。
     */
    private void deleteBreakPeriods(JdbcTemplate jdbcTemplate, String breakTypeId) {
        jdbcTemplate.update("DELETE FROM break_type_periods WHERE break_type_id = ?", breakTypeId);
    }

    /**
     * 休憩区分に属する休憩帯を表示順付きで登録する。
     */
    private void insertBreakPeriod(JdbcTemplate jdbcTemplate, String breakTypeId, int start, int end, int order) {
        jdbcTemplate.update("""
                INSERT INTO break_type_periods (break_type_id, start_minutes, end_minutes, display_order)
                VALUES (?, ?, ?, ?)
                """, breakTypeId, start, end, order);
    }

    /**
     * 通常・深夜の勤務時間帯を持つ勤務区分マスタをID単位で追加または更新する。
     */
    private void mergeWorkTimeType(JdbcTemplate jdbcTemplate, String id, String name, int regularStart, int regularEnd,
                                   int nightStart, int nightEnd, int order) {
        // Why not: 時刻文字列をDBで比較すると日付跨ぎの計算が複雑になるため、通常・深夜の時間帯を分で保持してTimeRulesで計算する。
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

    /**
     * テスト用社員を、通常勤務に必要な所属・休憩・勤務設定付きで生成する。
     */
    private AppUser employee(PasswordEncoder passwordEncoder) {
        return new AppUser("U001", "E001", "employee001", passwordEncoder.encode("password"),
                "山田 太郎", Role.EMPLOYEE, "G001", "第1開発グループ",
                "BT001", "標準休憩", "WT001", "通常勤務");
    }

    /**
     * テスト用上長を生成する。
     */
    private AppUser manager(PasswordEncoder passwordEncoder) {
        return new AppUser("U002", "M001", "manager001", passwordEncoder.encode("password"),
                "佐藤 花子", Role.MANAGER, "G900", "管理グループ",
                null, null, null, null);
    }

    /**
     * テスト用管理者を生成する。
     */
    private AppUser admin(PasswordEncoder passwordEncoder) {
        return new AppUser("U003", "A001", "admin001", passwordEncoder.encode("password"),
                "鈴木 一郎", Role.ADMIN, null, null, null, null, null, null);
    }
}

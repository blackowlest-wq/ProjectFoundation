/**
 * 日報入力・計算で参照するマスタデータのRepository。
 * 一覧取得だけでなく、入力値の存在チェックと勤務時間計算に必要な休憩・勤務区分設定も取得する。
 */
package com.example.dailyreport.master;

import com.example.dailyreport.common.ApiException;
import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

@Repository
public class MasterDataRepository {
    private final JdbcTemplate jdbcTemplate;

    public MasterDataRepository(JdbcTemplate jdbcTemplate) {
        this.jdbcTemplate = jdbcTemplate;
    }

    public List<ProjectOption> projects() {
        return jdbcTemplate.query("""
                SELECT project_id, project_name
                FROM projects
                WHERE enabled = 1
                ORDER BY display_order, project_id
                """, (rs, rowNum) -> new ProjectOption(rs.getString("project_id"), rs.getString("project_name")));
    }

    public List<WorkCategoryOption> workCategories() {
        return jdbcTemplate.query("""
                SELECT work_category_id, work_category_name
                FROM work_categories
                WHERE enabled = 1
                ORDER BY display_order, work_category_id
                """, (rs, rowNum) -> new WorkCategoryOption(rs.getString("work_category_id"), rs.getString("work_category_name")));
    }

    public List<HolidayTypeOption> holidayTypes() {
        return jdbcTemplate.query("""
                SELECT holiday_type, holiday_type_name, requires_work_time, allows_work_items
                FROM holiday_types
                WHERE enabled = 1
                ORDER BY display_order, holiday_type
                """, (rs, rowNum) -> new HolidayTypeOption(
                rs.getString("holiday_type"),
                rs.getString("holiday_type_name"),
                rs.getInt("requires_work_time") == 1,
                rs.getInt("allows_work_items") == 1));
    }

    public HolidayTypeOption requireHolidayType(String holidayType) {
        // 休日区分は業務ルール分岐の起点になるため、無効値は入力エラーとして即時に扱う。
        return jdbcTemplate.query("""
                        SELECT holiday_type, holiday_type_name, requires_work_time, allows_work_items
                        FROM holiday_types
                        WHERE holiday_type = ? AND enabled = 1
                        """,
                (rs, rowNum) -> new HolidayTypeOption(
                        rs.getString("holiday_type"),
                        rs.getString("holiday_type_name"),
                        rs.getInt("requires_work_time") == 1,
                        rs.getInt("allows_work_items") == 1),
                holidayType)
                .stream()
                .findFirst()
                .orElseThrow(() -> new ApiException(HttpStatus.BAD_REQUEST, "VALIDATION_ERROR", "入力内容が不正です。",
                        List.of(new com.example.dailyreport.common.ApiExceptionHandler.ErrorDetail(
                                "holidayType", "休日区分が存在しません。"))));
    }

    public WorkSettings requireWorkSettings(String breakTypeId, String workTimeTypeId) {
        // 休憩区分と勤務区分はセットで実勤務・通常/残業/深夜を計算するため、まとめて取得する。
        BreakTypeOption breakType = jdbcTemplate.query("""
                        SELECT break_type_id, break_type_name
                        FROM break_types
                        WHERE break_type_id = ? AND enabled = 1
                        """,
                (rs, rowNum) -> new BreakTypeOption(rs.getString("break_type_id"), rs.getString("break_type_name")),
                breakTypeId)
                .stream()
                .findFirst()
                .orElseThrow(() -> new ApiException(HttpStatus.BAD_REQUEST, "VALIDATION_ERROR", "入力内容が不正です。",
                        List.of(new com.example.dailyreport.common.ApiExceptionHandler.ErrorDetail(
                                "breakTypeId", "休憩区分が存在しません。"))));

        WorkTimeTypeOption workTimeType = jdbcTemplate.query("""
                        SELECT work_time_type_id, work_time_type_name, regular_start_minutes, regular_end_minutes,
                               night_start_minutes, night_end_minutes
                        FROM work_time_types
                        WHERE work_time_type_id = ? AND enabled = 1
                        """,
                (rs, rowNum) -> new WorkTimeTypeOption(
                        rs.getString("work_time_type_id"),
                        rs.getString("work_time_type_name"),
                        rs.getInt("regular_start_minutes"),
                        rs.getInt("regular_end_minutes"),
                        rs.getInt("night_start_minutes"),
                        rs.getInt("night_end_minutes")),
                workTimeTypeId)
                .stream()
                .findFirst()
                .orElseThrow(() -> new ApiException(HttpStatus.BAD_REQUEST, "VALIDATION_ERROR", "入力内容が不正です。",
                        List.of(new com.example.dailyreport.common.ApiExceptionHandler.ErrorDetail(
                                "workTimeTypeId", "勤務区分が存在しません。"))));

        List<TimePeriod> breakPeriods = jdbcTemplate.query("""
                        SELECT start_minutes, end_minutes
                        FROM break_type_periods
                        WHERE break_type_id = ?
                        ORDER BY display_order
                        """,
                (rs, rowNum) -> new TimePeriod(rs.getInt("start_minutes"), rs.getInt("end_minutes")),
                breakTypeId);

        return new WorkSettings(breakType, workTimeType, breakPeriods);
    }

    public boolean projectExists(String projectId) {
        Integer count = jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM projects WHERE project_id = ? AND enabled = 1", Integer.class, projectId);
        return count != null && count > 0;
    }

    public boolean workCategoryExists(String workCategoryId) {
        Integer count = jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM work_categories WHERE work_category_id = ? AND enabled = 1",
                Integer.class, workCategoryId);
        return count != null && count > 0;
    }

    public String projectName(String projectId) {
        // 無効化済みや削除済みマスタでも、保存済みIDを画面表示できるようIDをフォールバック表示する。
        return projects().stream()
                .filter(project -> project.projectId().equals(projectId))
                .map(ProjectOption::projectName)
                .findFirst()
                .orElse(projectId);
    }

    public String workCategoryName(String workCategoryId) {
        // 作業明細の表示では、マスタ名が取れない場合でも日報自体を表示不能にしない。
        return workCategories().stream()
                .filter(category -> category.workCategoryId().equals(workCategoryId))
                .map(WorkCategoryOption::workCategoryName)
                .findFirst()
                .orElse(workCategoryId);
    }

    public record ProjectOption(String projectId, String projectName) {
    }

    public record WorkCategoryOption(String workCategoryId, String workCategoryName) {
    }

    public record HolidayTypeOption(String holidayType, String holidayTypeName,
                                    boolean requiresWorkTime, boolean allowsWorkItems) {
    }

    public record BreakTypeOption(String breakTypeId, String breakTypeName) {
    }

    public record WorkTimeTypeOption(String workTimeTypeId, String workTimeTypeName,
                                     int regularStartMinutes, int regularEndMinutes,
                                     int nightStartMinutes, int nightEndMinutes) {
    }

    public record WorkSettings(BreakTypeOption breakType, WorkTimeTypeOption workTimeType, List<TimePeriod> breaks) {
    }

    public record TimePeriod(int startMinutes, int endMinutes) {
        public boolean contains(int minute) {
            if (endMinutes < startMinutes) {
                // 深夜帯のように日付をまたぐ時間帯は、開始以降または終了前を範囲内として扱う。
                return minute >= startMinutes || minute < endMinutes;
            }
            return minute >= startMinutes && minute < endMinutes;
        }

        public int overlapMinutes(int start, int end) {
            // 勤務時間帯と休憩時間帯の重なりだけを休憩控除対象にする。
            return Math.max(0, Math.min(end, endMinutes) - Math.max(start, startMinutes));
        }
    }
}

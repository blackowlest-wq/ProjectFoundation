/**
 * 月次集計のJdbcTemplate実装。
 * 対象月とAPPROVEDを各SQLで絞り、4種類の集計だけをDBへ依頼する。
 */
package com.example.dailyreport.monthlysummary;

import java.time.LocalDate;
import java.util.List;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

@Repository
public class JdbcMonthlySummaryRepository implements MonthlySummaryRepository {
    private final JdbcTemplate jdbcTemplate;

    public JdbcMonthlySummaryRepository(JdbcTemplate jdbcTemplate) {
        this.jdbcTemplate = jdbcTemplate;
    }

    @Override
    public List<MonthlySummaryResponse.EmployeeWorkSummary> employeeWorkSummaries(LocalDate from, LocalDate to) {
        return jdbcTemplate.query("""
                SELECT employee_id, employee_name, COALESCE(SUM(work_minutes), 0) AS total_work_minutes
                FROM daily_reports
                WHERE report_date >= ? AND report_date < ? AND approval_status = 'APPROVED'
                GROUP BY employee_id, employee_name
                ORDER BY employee_id
                """, (rs, rowNum) -> new MonthlySummaryResponse.EmployeeWorkSummary(
                rs.getString("employee_id"), rs.getString("employee_name"), rs.getInt("total_work_minutes")),
                from, to);
    }

    @Override
    public List<MonthlySummaryResponse.ProjectWorkSummary> projectWorkSummaries(LocalDate from, LocalDate to) {
        return jdbcTemplate.query("""
                SELECT wi.project_id, p.project_name, COALESCE(SUM(wi.work_minutes), 0) AS total_work_minutes
                FROM daily_reports dr
                JOIN daily_report_work_items wi ON wi.report_id = dr.report_id
                JOIN projects p ON p.project_id = wi.project_id
                WHERE dr.report_date >= ? AND dr.report_date < ? AND dr.approval_status = 'APPROVED'
                GROUP BY wi.project_id, p.project_name
                ORDER BY wi.project_id
                """, (rs, rowNum) -> new MonthlySummaryResponse.ProjectWorkSummary(
                rs.getString("project_id"), rs.getString("project_name"), rs.getInt("total_work_minutes")),
                from, to);
    }

    @Override
    public List<MonthlySummaryResponse.CategoryWorkSummary> categoryWorkSummaries(LocalDate from, LocalDate to) {
        return jdbcTemplate.query("""
                SELECT wi.work_category_id, wc.work_category_name,
                       COALESCE(SUM(wi.work_minutes), 0) AS total_work_minutes
                FROM daily_reports dr
                JOIN daily_report_work_items wi ON wi.report_id = dr.report_id
                JOIN work_categories wc ON wc.work_category_id = wi.work_category_id
                WHERE dr.report_date >= ? AND dr.report_date < ? AND dr.approval_status = 'APPROVED'
                GROUP BY wi.work_category_id, wc.work_category_name
                ORDER BY wi.work_category_id
                """, (rs, rowNum) -> new MonthlySummaryResponse.CategoryWorkSummary(
                rs.getString("work_category_id"), rs.getString("work_category_name"),
                rs.getInt("total_work_minutes")), from, to);
    }

    @Override
    public List<MonthlySummaryResponse.HolidayTypeSummary> holidayTypeSummaries(LocalDate from, LocalDate to) {
        return jdbcTemplate.query("""
                SELECT holiday_type, COUNT(*) AS total_days
                FROM daily_reports
                WHERE report_date >= ? AND report_date < ? AND approval_status = 'APPROVED'
                GROUP BY holiday_type
                ORDER BY holiday_type
                """, (rs, rowNum) -> new MonthlySummaryResponse.HolidayTypeSummary(
                rs.getString("holiday_type"), rs.getInt("total_days")), from, to);
    }
}

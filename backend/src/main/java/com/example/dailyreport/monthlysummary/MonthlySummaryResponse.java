/**
 * 月次集計APIのレスポンスDTO。
 */
package com.example.dailyreport.monthlysummary;

import java.util.List;

public record MonthlySummaryResponse(
        String yearMonth,
        List<EmployeeWorkSummary> employeeWorkSummaries,
        List<ProjectWorkSummary> projectWorkSummaries,
        List<CategoryWorkSummary> categoryWorkSummaries,
        List<HolidayTypeSummary> holidayTypeSummaries) {

    /**
     * 集計結果の配列を防御的にコピーし、JSON応答の契約を常に配列へ正規化する。
     */
    public MonthlySummaryResponse {
        employeeWorkSummaries = immutableList(employeeWorkSummaries);
        projectWorkSummaries = immutableList(projectWorkSummaries);
        categoryWorkSummaries = immutableList(categoryWorkSummaries);
        holidayTypeSummaries = immutableList(holidayTypeSummaries);
    }

    private static <T> List<T> immutableList(List<T> values) {
        return values == null ? List.of() : List.copyOf(values);
    }

    public record EmployeeWorkSummary(String employeeId, String employeeName, int totalWorkMinutes) {
    }

    public record ProjectWorkSummary(String projectId, String projectName, int totalWorkMinutes) {
    }

    public record CategoryWorkSummary(String workCategoryId, String workCategoryName, int totalWorkMinutes) {
    }

    public record HolidayTypeSummary(String holidayType, int totalDays) {
    }
}

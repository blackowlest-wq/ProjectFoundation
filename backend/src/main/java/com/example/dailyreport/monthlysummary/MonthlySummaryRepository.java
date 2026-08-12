/**
 * 承認済み日報を月単位で集約するRepository。
 */
package com.example.dailyreport.monthlysummary;

import java.time.LocalDate;
import java.util.List;

public interface MonthlySummaryRepository {
    List<MonthlySummaryResponse.EmployeeWorkSummary> employeeWorkSummaries(LocalDate from, LocalDate to);

    List<MonthlySummaryResponse.ProjectWorkSummary> projectWorkSummaries(LocalDate from, LocalDate to);

    List<MonthlySummaryResponse.CategoryWorkSummary> categoryWorkSummaries(LocalDate from, LocalDate to);

    List<MonthlySummaryResponse.HolidayTypeSummary> holidayTypeSummaries(LocalDate from, LocalDate to);
}

package com.example.dailyreport.monthlysummary;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doReturn;
import static org.mockito.Mockito.verify;

import java.time.LocalDate;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;

class JdbcMonthlySummaryRepositoryTest {
    @Test
    void issuesFourBoundedApprovedAggregateQueriesWithoutNPlusOne() {
        JdbcTemplate jdbcTemplate = org.mockito.Mockito.mock(JdbcTemplate.class);
        doReturn(List.of()).when(jdbcTemplate).query(anyString(), any(RowMapper.class), any(), any());
        JdbcMonthlySummaryRepository repository = new JdbcMonthlySummaryRepository(jdbcTemplate);
        LocalDate from = LocalDate.of(2028, 2, 1);
        LocalDate to = LocalDate.of(2028, 3, 1);

        repository.employeeWorkSummaries(from, to);
        repository.projectWorkSummaries(from, to);
        repository.categoryWorkSummaries(from, to);
        repository.holidayTypeSummaries(from, to);

        ArgumentCaptor<String> sqlCaptor = ArgumentCaptor.forClass(String.class);
        verify(jdbcTemplate, org.mockito.Mockito.times(4))
                .query(sqlCaptor.capture(), any(RowMapper.class), eq(from), eq(to));
        List<String> sql = sqlCaptor.getAllValues();
        assertThat(sql).hasSize(4);
        assertThat(sql).allSatisfy(statement -> {
            assertThat(statement).contains("report_date >= ?", "report_date < ?", "approval_status = 'APPROVED'");
        });
        assertThat(sql.get(0)).contains("COALESCE(SUM(work_minutes), 0)");
        assertThat(sql.get(1)).contains("daily_report_work_items", "SUM(wi.work_minutes)");
        assertThat(sql.get(2)).contains("work_categories", "SUM(wi.work_minutes)");
        assertThat(sql.get(3)).contains("COUNT(*)", "GROUP BY holiday_type");
    }
}

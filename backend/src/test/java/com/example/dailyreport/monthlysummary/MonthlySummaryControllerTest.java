package com.example.dailyreport.monthlysummary;

import static com.example.dailyreport.support.MockMvcTestSupport.loginAs;
import static org.assertj.core.api.Assertions.assertThat;
import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.matchesPattern;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.LocalDate;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.mock.web.MockHttpSession;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.jdbc.Sql;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Sql(statements = {
        "DELETE FROM daily_report_work_items WHERE report_id LIKE 'R-MONTH-%'",
        "DELETE FROM daily_reports WHERE report_id LIKE 'R-MONTH-%'"
}, executionPhase = Sql.ExecutionPhase.BEFORE_TEST_METHOD)
@Sql(statements = {
        "DELETE FROM daily_report_work_items WHERE report_id LIKE 'R-MONTH-%'",
        "DELETE FROM daily_reports WHERE report_id LIKE 'R-MONTH-%'"
}, executionPhase = Sql.ExecutionPhase.AFTER_TEST_METHOD)
class MonthlySummaryControllerTest {
    @Autowired
    MockMvc mockMvc;

    @Autowired
    ObjectMapper objectMapper;

    @Autowired
    JdbcTemplate jdbcTemplate;

    @Test
    void RT_F011_BE_001_adminGetsApprovedMonthlySummaryWithFourArrays() throws Exception {
        seedApprovedReport();
        MockHttpSession session = loginAs(mockMvc, objectMapper, "admin001");

        mockMvc.perform(get("/api/monthly-summaries")
                        .param("yearMonth", "2026-06")
                        .session(session))
                .andExpect(status().isOk())
                .andExpect(header().string("X-Request-Id", matchesPattern(
                        "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")))
                .andExpect(jsonPath("$.yearMonth", equalTo("2026-06")))
                .andExpect(jsonPath("$.employeeWorkSummaries[0].employeeId", equalTo("E001")))
                .andExpect(jsonPath("$.employeeWorkSummaries[0].totalWorkMinutes", equalTo(480)))
                .andExpect(jsonPath("$.projectWorkSummaries[0].projectId", equalTo("P001")))
                .andExpect(jsonPath("$.projectWorkSummaries[0].totalWorkMinutes", equalTo(480)))
                .andExpect(jsonPath("$.categoryWorkSummaries[0].workCategoryId", equalTo("WC001")))
                .andExpect(jsonPath("$.categoryWorkSummaries[0].totalWorkMinutes", equalTo(480)))
                .andExpect(jsonPath("$.holidayTypeSummaries[0].holidayType", equalTo("WORKDAY")))
                .andExpect(jsonPath("$.holidayTypeSummaries[0].totalDays", equalTo(1)));
    }

    @Test
    void RT_F011_BE_007_rejectsStrictYearMonthViolationsWithCommonError() throws Exception {
        MockHttpSession session = loginAs(mockMvc, objectMapper, "admin001");

        mockMvc.perform(get("/api/monthly-summaries")
                        .param("yearMonth", "2026-6")
                        .session(session))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code", equalTo("VALIDATION_ERROR")))
                .andExpect(jsonPath("$.details[0].field", equalTo("yearMonth")))
                .andExpect(jsonPath("$.requestId").isNotEmpty());
    }

    @Test
    void RT_F011_BE_007_rejectsMissingYearMonthWithValidationError() throws Exception {
        MockHttpSession session = loginAs(mockMvc, objectMapper, "admin001");

        mockMvc.perform(get("/api/monthly-summaries").session(session))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code", equalTo("VALIDATION_ERROR")))
                .andExpect(jsonPath("$.details[0].field", equalTo("yearMonth")))
                .andExpect(jsonPath("$.requestId").isNotEmpty());
    }

    @Test
    void RT_F011_BE_008_employeeCannotReadMonthlySummary() throws Exception {
        MockHttpSession session = loginAs(mockMvc, objectMapper, "employee001");

        MvcResult result = mockMvc.perform(get("/api/monthly-summaries")
                        .param("yearMonth", "2026-06")
                        .session(session))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code", equalTo("FORBIDDEN")))
                .andExpect(jsonPath("$.details", org.hamcrest.Matchers.hasSize(0)))
                .andExpect(jsonPath("$.yearMonth").doesNotExist())
                .andExpect(jsonPath("$.employeeWorkSummaries").doesNotExist())
                .andReturn();
        assertThat(result.getResponse().getHeader("X-Request-Id"))
                .isEqualTo(objectMapper.readTree(result.getResponse().getContentAsString()).get("requestId").asText());
    }

    @Test
    void RT_F011_BE_008_managerCannotReadMonthlySummary() throws Exception {
        MockHttpSession session = loginAs(mockMvc, objectMapper, "manager001");

        mockMvc.perform(get("/api/monthly-summaries")
                        .param("yearMonth", "2026-06")
                        .session(session))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code", equalTo("FORBIDDEN")))
                .andExpect(jsonPath("$.details", org.hamcrest.Matchers.hasSize(0)))
                .andExpect(jsonPath("$.projectWorkSummaries").doesNotExist());
    }

    @Test
    void RT_F011_BE_009_013_unauthenticatedMonthlySummaryReturnsCommon401() throws Exception {
        MvcResult result = mockMvc.perform(get("/api/monthly-summaries").param("yearMonth", "2026-06"))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code", equalTo("UNAUTHORIZED")))
                .andExpect(jsonPath("$.details", org.hamcrest.Matchers.hasSize(0)))
                .andExpect(jsonPath("$.holidayTypeSummaries").doesNotExist())
                .andReturn();
        assertThat(result.getResponse().getHeader("X-Request-Id"))
                .isEqualTo(objectMapper.readTree(result.getResponse().getContentAsString()).get("requestId").asText());
    }

    @Test
    void RT_F011_BE_014_approvedHolidayWithoutWorkMinutesIsReturnedAsZeroEmployeeMinutes() throws Exception {
        seedApprovedHolidayWithoutWorkMinutes();
        MockHttpSession session = loginAs(mockMvc, objectMapper, "admin001");

        mockMvc.perform(get("/api/monthly-summaries")
                        .param("yearMonth", "2026-07")
                        .session(session))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.employeeWorkSummaries", org.hamcrest.Matchers.hasSize(1)))
                .andExpect(jsonPath("$.employeeWorkSummaries[0].employeeId", equalTo("E001")))
                .andExpect(jsonPath("$.employeeWorkSummaries[0].totalWorkMinutes", equalTo(0)))
                .andExpect(jsonPath("$.projectWorkSummaries", org.hamcrest.Matchers.hasSize(0)))
                .andExpect(jsonPath("$.categoryWorkSummaries", org.hamcrest.Matchers.hasSize(0)))
                .andExpect(jsonPath("$.holidayTypeSummaries[0].holidayType", equalTo("PAID_LEAVE")))
                .andExpect(jsonPath("$.holidayTypeSummaries[0].totalDays", equalTo(1)));
    }

    private void seedApprovedReport() {
        jdbcTemplate.update("""
                INSERT INTO daily_reports (
                    report_id, employee_user_id, employee_id, employee_name, group_id, group_name,
                    report_date, holiday_type, break_type_id, break_type_name, work_time_type_id, work_time_type_name,
                    start_time_minutes, end_time_minutes, break_minutes, work_minutes, regular_work_minutes,
                    overtime_work_minutes, night_work_minutes, remarks, approval_status,
                    approver_user_id, approver_name, approved_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, "R-MONTH-001", "U001", "E001", "山田 太郎", "G001", "第1開発グループ",
                LocalDate.of(2026, 6, 15), "WORKDAY", "BT001", "標準休憩", "WT001", "通常勤務",
                540, 1080, 60, 480, 480, 0, 0, "月次テスト", "APPROVED", "U002", "佐藤 花子",
                java.time.OffsetDateTime.parse("2026-06-16T09:30:00+09:00"));
        jdbcTemplate.update("""
                INSERT INTO daily_report_work_items
                    (work_item_id, report_id, project_id, work_category_id, work_minutes, display_order)
                VALUES (?, ?, ?, ?, ?, ?)
                """, "WI-MONTH-001", "R-MONTH-001", "P001", "WC001", 480, 1);
    }

    private void seedApprovedHolidayWithoutWorkMinutes() {
        jdbcTemplate.update("""
                INSERT INTO daily_reports (
                    report_id, employee_user_id, employee_id, employee_name, group_id, group_name,
                    report_date, holiday_type, break_type_id, break_type_name, work_time_type_id, work_time_type_name,
                    start_time_minutes, end_time_minutes, break_minutes, work_minutes, regular_work_minutes,
                    overtime_work_minutes, night_work_minutes, remarks, approval_status,
                    approver_user_id, approver_name, approved_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, "R-MONTH-002", "U001", "E001", "山田 太郎", "G001", "第1開発グループ",
                LocalDate.of(2026, 7, 1), "PAID_LEAVE", "BT001", "標準休憩", "WT001", "通常勤務",
                null, null, null, null, null, 0, 0, "月次休暇テスト", "APPROVED", "U002", "佐藤 花子",
                java.time.OffsetDateTime.parse("2026-07-02T09:30:00+09:00"));
    }
}

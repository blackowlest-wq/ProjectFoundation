package com.example.dailyreport.report;

import static com.example.dailyreport.report.support.DailyReportTestSupport.seedReport;
import static com.example.dailyreport.report.support.DailyReportTestSupport.seedUser;
import static com.example.dailyreport.support.MockMvcTestSupport.loginAs;
import static org.assertj.core.api.Assertions.assertThat;
import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.notNullValue;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.csrf;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.LocalDate;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.mock.web.MockHttpSession;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.jdbc.Sql;
import org.springframework.test.web.servlet.MockMvc;

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Sql(statements = {
        "DELETE FROM daily_report_work_items",
        "DELETE FROM daily_reports"
}, executionPhase = Sql.ExecutionPhase.BEFORE_TEST_METHOD)
class DailyReportApprovalControllerTest {
    @Autowired
    MockMvc mockMvc;

    @Autowired
    ObjectMapper objectMapper;

    @Autowired
    JdbcTemplate jdbcTemplate;

    @Test
    void managerCanApprovePendingReport() throws Exception {
        seedReport(jdbcTemplate, "R-APPROVE-001", "U001", "E001", "山田 太郎",
                "G001", "第1開発グループ", LocalDate.of(2026, 6, 2), "PENDING");
        MockHttpSession session = loginAs(mockMvc, objectMapper, "manager001");

        mockMvc.perform(post("/api/daily-reports/R-APPROVE-001/approve")
                        .with(csrf()).session(session))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.reportId", equalTo("R-APPROVE-001")))
                .andExpect(jsonPath("$.approvalStatus", equalTo("APPROVED")))
                .andExpect(jsonPath("$.approverId", equalTo("U002")))
                .andExpect(jsonPath("$.approverName", equalTo("佐藤 上長")))
                .andExpect(jsonPath("$.approvedAt", notNullValue()));

        Map<String, Object> row = reportRow("R-APPROVE-001");
        assertThat(row.get("APPROVAL_STATUS")).isEqualTo("APPROVED");
        assertThat(row.get("APPROVER_USER_ID")).isEqualTo("U002");
        assertThat(row.get("APPROVER_NAME")).isEqualTo("佐藤 上長");
        assertThat(row.get("APPROVED_AT")).isNotNull();
    }

    @Test
    void managerCanRejectPendingReportWithTrimmedComment() throws Exception {
        seedReport(jdbcTemplate, "R-REJECT-001", "U001", "E001", "山田 太郎",
                "G001", "第1開発グループ", LocalDate.of(2026, 6, 3), "PENDING");
        MockHttpSession session = loginAs(mockMvc, objectMapper, "manager001");

        mockMvc.perform(post("/api/daily-reports/R-REJECT-001/reject")
                        .with(csrf()).session(session)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"rejectComment\":\"  作業時間を確認してください。  \"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.reportId", equalTo("R-REJECT-001")))
                .andExpect(jsonPath("$.approvalStatus", equalTo("REJECTED")))
                .andExpect(jsonPath("$.rejectorId", equalTo("U002")))
                .andExpect(jsonPath("$.rejectorName", equalTo("佐藤 上長")))
                .andExpect(jsonPath("$.rejectedAt", notNullValue()))
                .andExpect(jsonPath("$.rejectComment", equalTo("作業時間を確認してください。")));

        Map<String, Object> row = reportRow("R-REJECT-001");
        assertThat(row.get("APPROVAL_STATUS")).isEqualTo("REJECTED");
        assertThat(row.get("REJECTOR_USER_ID")).isEqualTo("U002");
        assertThat(row.get("REJECTOR_NAME")).isEqualTo("佐藤 上長");
        assertThat(row.get("REJECTED_AT")).isNotNull();
        assertThat(row.get("REJECT_COMMENT")).isEqualTo("作業時間を確認してください。");
    }

    @Test
    void managerCannotApproveUnauthorizedOrNonPendingReportsAndRowsStayUnchanged() throws Exception {
        seedReport(jdbcTemplate, "R-APPROVE-OUTSIDE", "U099", "E099", "他部署 社員",
                "G099", "他部署グループ", LocalDate.of(2026, 6, 4), "PENDING");
        seedReport(jdbcTemplate, "R-APPROVE-DRAFT", "U001", "E001", "山田 太郎",
                "G001", "第1開発グループ", LocalDate.of(2026, 6, 5), "DRAFT");
        MockHttpSession session = loginAs(mockMvc, objectMapper, "manager001");

        mockMvc.perform(post("/api/daily-reports/R-APPROVE-OUTSIDE/approve").with(csrf()).session(session))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code", equalTo("FORBIDDEN")));
        mockMvc.perform(post("/api/daily-reports/R-APPROVE-DRAFT/approve").with(csrf()).session(session))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code", equalTo("INVALID_STATUS")));

        assertUnchanged(reportRow("R-APPROVE-OUTSIDE"), "PENDING");
        assertUnchanged(reportRow("R-APPROVE-DRAFT"), "DRAFT");
    }

    @Test
    void managerCannotRejectUnauthorizedOrNonPendingReportsAndRowsStayUnchanged() throws Exception {
        seedReport(jdbcTemplate, "R-REJECT-OUTSIDE", "U099", "E099", "他部署 社員",
                "G099", "他部署グループ", LocalDate.of(2026, 6, 6), "PENDING");
        seedReport(jdbcTemplate, "R-REJECT-APPROVED", "U001", "E001", "山田 太郎",
                "G001", "第1開発グループ", LocalDate.of(2026, 6, 7), "APPROVED");
        MockHttpSession session = loginAs(mockMvc, objectMapper, "manager001");

        mockMvc.perform(post("/api/daily-reports/R-REJECT-OUTSIDE/reject")
                        .with(csrf()).session(session)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"rejectComment\":\"確認してください。\"}"))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code", equalTo("FORBIDDEN")));
        mockMvc.perform(post("/api/daily-reports/R-REJECT-APPROVED/reject")
                        .with(csrf()).session(session)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"rejectComment\":\"確認してください。\"}"))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code", equalTo("INVALID_STATUS")));

        assertUnchanged(reportRow("R-REJECT-OUTSIDE"), "PENDING");
        assertUnchanged(reportRow("R-REJECT-APPROVED"), "APPROVED");
    }

    @Test
    void rejectCommentIsNormalizedAndValidatedByBackend() throws Exception {
        seedReport(jdbcTemplate, "R-REJECT-VALIDATION", "U001", "E001", "山田 太郎",
                "G001", "第1開発グループ", LocalDate.of(2026, 6, 8), "PENDING");
        MockHttpSession session = loginAs(mockMvc, objectMapper, "manager001");

        mockMvc.perform(post("/api/daily-reports/R-REJECT-VALIDATION/reject")
                        .with(csrf()).session(session)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"rejectComment\":\"   \"}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code", equalTo("VALIDATION_ERROR")));

        String tooLongAfterTrim = " ".repeat(2) + "x".repeat(1001) + " ".repeat(2);
        mockMvc.perform(post("/api/daily-reports/R-REJECT-VALIDATION/reject")
                        .with(csrf()).session(session)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(Map.of("rejectComment", tooLongAfterTrim))))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code", equalTo("VALIDATION_ERROR")));

        assertUnchanged(reportRow("R-REJECT-VALIDATION"), "PENDING");
    }

    @Test
    void approveAndRejectRequireAuthenticationAndCsrfAndLeaveRowsUnchanged() throws Exception {
        seedReport(jdbcTemplate, "R-APPROVE-SECURITY", "U001", "E001", "山田 太郎",
                "G001", "第1開発グループ", LocalDate.of(2026, 6, 9), "PENDING");
        seedReport(jdbcTemplate, "R-REJECT-SECURITY", "U001", "E001", "山田 太郎",
                "G001", "第1開発グループ", LocalDate.of(2026, 6, 10), "PENDING");
        MockHttpSession session = loginAs(mockMvc, objectMapper, "manager001");

        mockMvc.perform(post("/api/daily-reports/R-APPROVE-SECURITY/approve").with(csrf()))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code", equalTo("UNAUTHORIZED")));
        mockMvc.perform(post("/api/daily-reports/R-REJECT-SECURITY/reject")
                        .with(csrf())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"rejectComment\":\"確認してください。\"}"))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code", equalTo("UNAUTHORIZED")));

        // CSRF filters run before authorization for unsafe requests, so requests without a token
        // follow the established mutation contract and receive the common 403 response.
        mockMvc.perform(post("/api/daily-reports/R-APPROVE-SECURITY/approve"))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code", equalTo("FORBIDDEN")));
        mockMvc.perform(post("/api/daily-reports/R-REJECT-SECURITY/reject")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"rejectComment\":\"確認してください。\"}"))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code", equalTo("FORBIDDEN")));
        mockMvc.perform(post("/api/daily-reports/R-APPROVE-SECURITY/approve").session(session))
                .andExpect(status().isForbidden());
        mockMvc.perform(post("/api/daily-reports/R-REJECT-SECURITY/reject")
                        .session(session)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"rejectComment\":\"確認してください。\"}"))
                .andExpect(status().isForbidden());

        assertUnchanged(reportRow("R-APPROVE-SECURITY"), "PENDING");
        assertUnchanged(reportRow("R-REJECT-SECURITY"), "PENDING");
    }

    @Test
    void employeeAndAdminCannotApproveOrRejectReports() throws Exception {
        seedReport(jdbcTemplate, "R-ROLE-EMPLOYEE", "U001", "E001", "山田 太郎",
                "G001", "第1開発グループ", LocalDate.of(2026, 6, 11), "PENDING");
        seedReport(jdbcTemplate, "R-ROLE-ADMIN", "U001", "E001", "山田 太郎",
                "G001", "第1開発グループ", LocalDate.of(2026, 6, 12), "PENDING");
        MockHttpSession employeeSession = loginAs(mockMvc, objectMapper, "employee001");
        MockHttpSession adminSession = loginAs(mockMvc, objectMapper, "admin001");

        mockMvc.perform(post("/api/daily-reports/R-ROLE-EMPLOYEE/approve")
                        .with(csrf()).session(employeeSession))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code", equalTo("FORBIDDEN")));
        mockMvc.perform(post("/api/daily-reports/R-ROLE-ADMIN/reject")
                        .with(csrf()).session(adminSession)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"rejectComment\":\"確認してください。\"}"))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code", equalTo("FORBIDDEN")));

        assertUnchanged(reportRow("R-ROLE-EMPLOYEE"), "PENDING");
        assertUnchanged(reportRow("R-ROLE-ADMIN"), "PENDING");
    }

    private Map<String, Object> reportRow(String reportId) {
        return jdbcTemplate.queryForMap("""
                SELECT approval_status, approver_user_id, approver_name, approved_at,
                       rejector_user_id, rejector_name, rejected_at, reject_comment
                FROM daily_reports WHERE report_id = ?
                """, reportId);
    }

    private void assertUnchanged(Map<String, Object> row, String status) {
        assertThat(row.get("APPROVAL_STATUS")).isEqualTo(status);
        assertThat(row.get("APPROVER_USER_ID")).isNull();
        assertThat(row.get("APPROVER_NAME")).isNull();
        assertThat(row.get("APPROVED_AT")).isNull();
        assertThat(row.get("REJECTOR_USER_ID")).isNull();
        assertThat(row.get("REJECTOR_NAME")).isNull();
        assertThat(row.get("REJECTED_AT")).isNull();
        assertThat(row.get("REJECT_COMMENT")).isNull();
    }
}

package com.example.dailyreport.report;

import static com.example.dailyreport.report.support.DailyReportTestSupport.seedReport;
import static com.example.dailyreport.report.support.DailyReportTestSupport.seedUser;
import static com.example.dailyreport.support.MockMvcTestSupport.loginAs;
import static org.assertj.core.api.Assertions.assertThat;
import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.notNullValue;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.csrf;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
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
        "DELETE FROM daily_reports",
        "DELETE FROM users WHERE user_id = 'U099'"
}, executionPhase = Sql.ExecutionPhase.BEFORE_TEST_METHOD)
@Sql(statements = {
        "DELETE FROM daily_report_work_items",
        "DELETE FROM daily_reports",
        "DELETE FROM users WHERE user_id = 'U099'"
}, executionPhase = Sql.ExecutionPhase.AFTER_TEST_METHOD)
class DailyReportApprovalControllerTest {
    @Autowired
    MockMvc mockMvc;

    @Autowired
    ObjectMapper objectMapper;

    @Autowired
    JdbcTemplate jdbcTemplate;

    @Test
    void rtAprBe001ManagerApprovesPendingReportAndDetailReturnsApprovalAudit() throws Exception {
        seedReport(jdbcTemplate, "R-APPROVE-001", "U001", "E001", "山田 太郎",
                "G001", "第1開発グループ", LocalDate.of(2026, 6, 2), "PENDING");
        MockHttpSession session = loginAs(mockMvc, objectMapper, "manager001");

        mockMvc.perform(post("/api/daily-reports/R-APPROVE-001/approve")
                        .with(csrf()).session(session))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.reportId", equalTo("R-APPROVE-001")))
                .andExpect(jsonPath("$.approvalStatus", equalTo("APPROVED")))
                .andExpect(jsonPath("$.approverId", equalTo("U002")))
                .andExpect(jsonPath("$.approverName", equalTo("佐藤 花子")))
                .andExpect(jsonPath("$.approvedAt", notNullValue()));

        Map<String, Object> row = reportRow("R-APPROVE-001");
        assertThat(row.get("APPROVAL_STATUS")).isEqualTo("APPROVED");
        assertThat(row.get("APPROVER_USER_ID")).isEqualTo("U002");
        assertThat(row.get("APPROVER_NAME")).isEqualTo("佐藤 花子");
        assertThat(row.get("APPROVED_AT")).isNotNull();

        mockMvc.perform(get("/api/daily-reports/R-APPROVE-001").session(session))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.approvalStatus", equalTo("APPROVED")))
                .andExpect(jsonPath("$.approverId", equalTo("U002")))
                .andExpect(jsonPath("$.approverName", equalTo("佐藤 花子")))
                .andExpect(jsonPath("$.approvedAt", notNullValue()));
    }

    @Test
    void rtAprBe003ManagerRejectsPendingReportAndDetailReturnsRejectionAudit() throws Exception {
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
                .andExpect(jsonPath("$.rejectorName", equalTo("佐藤 花子")))
                .andExpect(jsonPath("$.rejectedAt", notNullValue()))
                .andExpect(jsonPath("$.rejectComment", equalTo("作業時間を確認してください。")));

        Map<String, Object> row = reportRow("R-REJECT-001");
        assertThat(row.get("APPROVAL_STATUS")).isEqualTo("REJECTED");
        assertThat(row.get("REJECTOR_USER_ID")).isEqualTo("U002");
        assertThat(row.get("REJECTOR_NAME")).isEqualTo("佐藤 花子");
        assertThat(row.get("REJECTED_AT")).isNotNull();
        assertThat(row.get("REJECT_COMMENT")).isEqualTo("作業時間を確認してください。");

        mockMvc.perform(get("/api/daily-reports/R-REJECT-001").session(session))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.approvalStatus", equalTo("REJECTED")))
                .andExpect(jsonPath("$.rejectorId", equalTo("U002")))
                .andExpect(jsonPath("$.rejectorName", equalTo("佐藤 花子")))
                .andExpect(jsonPath("$.rejectedAt", notNullValue()))
                .andExpect(jsonPath("$.rejectComment", equalTo("作業時間を確認してください。")));
    }

    @Test
    // RT-APR-BE-006 / TC-APR-008
    void rtAprBe006PendingApprovalsFilterPermittedGroupAndEmployeeOrderOnlyPendingReports() throws Exception {
        seedUser(jdbcTemplate, "U099", "E099", "other001", "他部署 社員", "EMPLOYEE", "G099", "他部署グループ");
        seedReport(jdbcTemplate, "R-PENDING-FIRST-DAY", "U002", "M001", "佐藤 花子",
                "G001", "第1開発グループ", LocalDate.of(2026, 6, 7), "PENDING");
        seedReport(jdbcTemplate, "R-PENDING-SECOND-DAY-E001", "U001", "E001", "山田 太郎",
                "G001", "第1開発グループ", LocalDate.of(2026, 6, 8), "PENDING");
        seedReport(jdbcTemplate, "R-PENDING-SECOND-DAY-M001", "U002", "M001", "佐藤 花子",
                "G001", "第1開発グループ", LocalDate.of(2026, 6, 8), "PENDING");
        seedReport(jdbcTemplate, "R-PENDING-OUT", "U099", "E099", "他部署 社員",
                "G099", "他部署グループ", LocalDate.of(2026, 6, 8), "PENDING");
        seedReport(jdbcTemplate, "R-DRAFT-IN", "U001", "E001", "山田 太郎",
                "G001", "第1開発グループ", LocalDate.of(2026, 6, 9), "DRAFT");
        MockHttpSession session = loginAs(mockMvc, objectMapper, "manager001");

        mockMvc.perform(get("/api/daily-reports/pending-approvals")
                        .param("dateFrom", "2026-06-01")
                        .param("dateTo", "2026-06-30")
                        .session(session))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()", equalTo(3)))
                .andExpect(jsonPath("$[0].reportId", equalTo("R-PENDING-FIRST-DAY")))
                .andExpect(jsonPath("$[1].reportId", equalTo("R-PENDING-SECOND-DAY-E001")))
                .andExpect(jsonPath("$[2].reportId", equalTo("R-PENDING-SECOND-DAY-M001")))
                .andExpect(jsonPath("$[0].approvalStatus", equalTo("PENDING")))
                .andExpect(jsonPath("$[1].approvalStatus", equalTo("PENDING")))
                .andExpect(jsonPath("$[2].approvalStatus", equalTo("PENDING")));

        mockMvc.perform(get("/api/daily-reports/pending-approvals")
                        .param("dateFrom", "2026-06-01")
                        .param("dateTo", "2026-06-30")
                        .param("groupId", "G001")
                        .param("employeeId", "E001")
                        .session(session))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()", equalTo(1)))
                .andExpect(jsonPath("$[0].reportId", equalTo("R-PENDING-SECOND-DAY-E001")))
                .andExpect(jsonPath("$[0].groupId", equalTo("G001")))
                .andExpect(jsonPath("$[0].employeeId", equalTo("E001")));

        mockMvc.perform(get("/api/daily-reports/pending-approvals")
                        .param("dateFrom", "2026-06-01")
                        .param("dateTo", "2026-06-30")
                        .param("groupId", "G099")
                        .session(session))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()", equalTo(0)));
    }

    @Test
    // RT-APR-BE-007 / TC-APR-009
    void rtAprBe007PendingApprovalsAuthenticateBeforeDateValidationAndRejectNonManagers() throws Exception {
        mockMvc.perform(get("/api/daily-reports/pending-approvals"))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code", equalTo("UNAUTHORIZED")));

        MockHttpSession employeeSession = loginAs(mockMvc, objectMapper, "employee001");
        mockMvc.perform(get("/api/daily-reports/pending-approvals").session(employeeSession))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code", equalTo("FORBIDDEN")));
        mockMvc.perform(get("/api/daily-reports/pending-approvals")
                        .param("dateFrom", "2026-06-01")
                        .param("dateTo", "2026-06-30")
                        .session(employeeSession))
                .andExpect(status().isForbidden());

        MockHttpSession adminSession = loginAs(mockMvc, objectMapper, "admin001");
        mockMvc.perform(get("/api/daily-reports/pending-approvals").session(adminSession))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code", equalTo("FORBIDDEN")));
        mockMvc.perform(get("/api/daily-reports/pending-approvals")
                        .param("dateFrom", "2026-06-01")
                        .param("dateTo", "2026-06-30")
                        .session(adminSession))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code", equalTo("FORBIDDEN")));
    }

    @Test
    // RT-APR-BE-006 / TC-APR-008
    void rtAprBe006PendingApprovalsReturnEmptyArrayForManagerWithoutPermittedGroups() throws Exception {
        seedOutsideManager();
        seedReport(jdbcTemplate, "R-PENDING-PERMITTED", "U001", "E001", "山田 太郎",
                "G001", "第1開発グループ", LocalDate.of(2026, 6, 8), "PENDING");
        MockHttpSession outsideManagerSession = loginAs(mockMvc, objectMapper, "manager099");

        mockMvc.perform(get("/api/daily-reports/pending-approvals")
                        .param("dateFrom", "2026-06-01")
                        .param("dateTo", "2026-06-30")
                        .session(outsideManagerSession))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()", equalTo(0)));
    }

    @Test
    // RT-APR-BE-006 / TC-APR-008
    void rtAprBe006PendingApprovalsRejectMissingReverseAndOver366DayManagerRanges() throws Exception {
        MockHttpSession session = loginAs(mockMvc, objectMapper, "manager001");

        mockMvc.perform(get("/api/daily-reports/pending-approvals")
                        .param("dateTo", "2026-06-30")
                        .session(session))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code", equalTo("VALIDATION_ERROR")));
        mockMvc.perform(get("/api/daily-reports/pending-approvals")
                        .param("dateFrom", "2026-06-01")
                        .session(session))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code", equalTo("VALIDATION_ERROR")));
        mockMvc.perform(get("/api/daily-reports/pending-approvals")
                        .param("dateFrom", "2026-06-30")
                        .param("dateTo", "2026-06-01")
                        .session(session))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code", equalTo("VALIDATION_ERROR")));
        mockMvc.perform(get("/api/daily-reports/pending-approvals")
                        .param("dateFrom", "2025-01-01")
                        .param("dateTo", "2026-01-03")
                        .session(session))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code", equalTo("VALIDATION_ERROR")));
    }

    @Test
    // RT-APR-BE-008 / TC-APR-010
    void rtAprBe008ApprovedDetailAllowsOwnerAssignedManagerAndAdminWithoutLeakingToOutsideManager() throws Exception {
        seedReport(jdbcTemplate, "R-DETAIL-APPROVED", "U001", "E001", "山田 太郎",
                "G001", "第1開発グループ", LocalDate.of(2026, 6, 10), "PENDING");
        MockHttpSession managerSession = loginAs(mockMvc, objectMapper, "manager001");
        mockMvc.perform(post("/api/daily-reports/R-DETAIL-APPROVED/approve").with(csrf()).session(managerSession))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.approvalStatus", equalTo("APPROVED")))
                .andExpect(jsonPath("$.approverId", equalTo("U002")))
                .andExpect(jsonPath("$.approvedAt", notNullValue()));

        assertApprovedAuditVisible(loginAs(mockMvc, objectMapper, "employee001"));
        assertApprovedAuditVisible(managerSession);
        assertApprovedAuditVisible(loginAs(mockMvc, objectMapper, "admin001"));

        seedOutsideManager();
        assertAuditIsNotLeakedToOutsideManager("R-DETAIL-APPROVED", loginAs(mockMvc, objectMapper, "manager099"));
        mockMvc.perform(get("/api/daily-reports/not-found-approved").session(managerSession))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code", equalTo("NOT_FOUND")));
    }

    @Test
    // RT-APR-BE-008 / TC-APR-010
    void rtAprBe008RejectedDetailAllowsOwnerAssignedManagerAndAdminWithoutLeakingToOutsideManager() throws Exception {
        seedReport(jdbcTemplate, "R-DETAIL-REJECTED", "U001", "E001", "山田 太郎",
                "G001", "第1開発グループ", LocalDate.of(2026, 6, 11), "PENDING");
        MockHttpSession managerSession = loginAs(mockMvc, objectMapper, "manager001");
        mockMvc.perform(post("/api/daily-reports/R-DETAIL-REJECTED/reject")
                        .with(csrf()).session(managerSession)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(rejectJson("監査情報を確認してください。")))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.approvalStatus", equalTo("REJECTED")))
                .andExpect(jsonPath("$.rejectorId", equalTo("U002")))
                .andExpect(jsonPath("$.rejectedAt", notNullValue()))
                .andExpect(jsonPath("$.rejectComment", equalTo("監査情報を確認してください。")));

        assertRejectedAuditVisible(loginAs(mockMvc, objectMapper, "employee001"));
        assertRejectedAuditVisible(managerSession);
        assertRejectedAuditVisible(loginAs(mockMvc, objectMapper, "admin001"));

        seedOutsideManager();
        assertAuditIsNotLeakedToOutsideManager("R-DETAIL-REJECTED", loginAs(mockMvc, objectMapper, "manager099"));
    }

    @Test
    void rtAprBe002ApproveRejectsAllNonPendingAndOutsideReportsWithoutChanges() throws Exception {
        seedOutsideEmployee();
        seedReport(jdbcTemplate, "R-APPROVE-OUTSIDE", "U099", "E099", "他部署 社員",
                "G099", "他部署グループ", LocalDate.of(2026, 6, 4), "PENDING");
        seedReport(jdbcTemplate, "R-APPROVE-DRAFT", "U001", "E001", "山田 太郎", "G001", "第1開発グループ", LocalDate.of(2026, 6, 5), "DRAFT");
        seedReport(jdbcTemplate, "R-APPROVE-REJECTED", "U001", "E001", "山田 太郎", "G001", "第1開発グループ", LocalDate.of(2026, 6, 6), "REJECTED");
        seedReport(jdbcTemplate, "R-APPROVE-APPROVED", "U001", "E001", "山田 太郎", "G001", "第1開発グループ", LocalDate.of(2026, 6, 7), "APPROVED");
        MockHttpSession session = loginAs(mockMvc, objectMapper, "manager001");

        mockMvc.perform(post("/api/daily-reports/R-APPROVE-OUTSIDE/approve").with(csrf()).session(session))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code", equalTo("FORBIDDEN")));
        mockMvc.perform(post("/api/daily-reports/R-APPROVE-DRAFT/approve").with(csrf()).session(session))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code", equalTo("INVALID_STATUS")));
        mockMvc.perform(post("/api/daily-reports/R-APPROVE-REJECTED/approve").with(csrf()).session(session))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code", equalTo("INVALID_STATUS")));
        mockMvc.perform(post("/api/daily-reports/R-APPROVE-APPROVED/approve").with(csrf()).session(session))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code", equalTo("INVALID_STATUS")));

        assertUnchanged(reportRow("R-APPROVE-OUTSIDE"), "PENDING");
        assertUnchanged(reportRow("R-APPROVE-DRAFT"), "DRAFT");
        assertUnchanged(reportRow("R-APPROVE-REJECTED"), "REJECTED");
        assertUnchanged(reportRow("R-APPROVE-APPROVED"), "APPROVED");
    }

    @Test
    void rtAprBe004RejectRejectsAllNonPendingAndOutsideReportsWithoutChanges() throws Exception {
        seedOutsideEmployee();
        seedReport(jdbcTemplate, "R-REJECT-OUTSIDE", "U099", "E099", "他部署 社員",
                "G099", "他部署グループ", LocalDate.of(2026, 6, 6), "PENDING");
        seedReport(jdbcTemplate, "R-REJECT-DRAFT", "U001", "E001", "山田 太郎", "G001", "第1開発グループ", LocalDate.of(2026, 6, 7), "DRAFT");
        seedReport(jdbcTemplate, "R-REJECT-REJECTED", "U001", "E001", "山田 太郎", "G001", "第1開発グループ", LocalDate.of(2026, 6, 8), "REJECTED");
        seedReport(jdbcTemplate, "R-REJECT-APPROVED", "U001", "E001", "山田 太郎", "G001", "第1開発グループ", LocalDate.of(2026, 6, 9), "APPROVED");
        MockHttpSession session = loginAs(mockMvc, objectMapper, "manager001");

        mockMvc.perform(post("/api/daily-reports/R-REJECT-OUTSIDE/reject")
                        .with(csrf()).session(session)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"rejectComment\":\"確認してください。\"}"))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code", equalTo("FORBIDDEN")));
        mockMvc.perform(post("/api/daily-reports/R-REJECT-DRAFT/reject")
                        .with(csrf()).session(session)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(rejectJson("確認してください。")))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code", equalTo("INVALID_STATUS")));
        mockMvc.perform(post("/api/daily-reports/R-REJECT-REJECTED/reject")
                        .with(csrf()).session(session)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(rejectJson("確認してください。")))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code", equalTo("INVALID_STATUS")));
        mockMvc.perform(post("/api/daily-reports/R-REJECT-APPROVED/reject")
                        .with(csrf()).session(session)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"rejectComment\":\"確認してください。\"}"))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code", equalTo("INVALID_STATUS")));

        assertUnchanged(reportRow("R-REJECT-OUTSIDE"), "PENDING");
        assertUnchanged(reportRow("R-REJECT-DRAFT"), "DRAFT");
        assertUnchanged(reportRow("R-REJECT-REJECTED"), "REJECTED");
        assertUnchanged(reportRow("R-REJECT-APPROVED"), "APPROVED");
    }

    @Test
    void rtAprBe005RejectCommentBoundaryValidationLeavesInvalidRowsUnchangedAndStoresTrimmedMaximum() throws Exception {
        seedReport(jdbcTemplate, "R-REJECT-VALIDATION", "U001", "E001", "山田 太郎",
                "G001", "第1開発グループ", LocalDate.of(2026, 6, 8), "PENDING");
        MockHttpSession session = loginAs(mockMvc, objectMapper, "manager001");

        mockMvc.perform(post("/api/daily-reports/R-REJECT-VALIDATION/reject")
                        .with(csrf()).session(session)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"rejectComment\":\"   \"}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code", equalTo("VALIDATION_ERROR")));
        assertUnchanged(reportRow("R-REJECT-VALIDATION"), "PENDING");

        String tooLongAfterTrim = " ".repeat(2) + "x".repeat(1001) + " ".repeat(2);
        mockMvc.perform(post("/api/daily-reports/R-REJECT-VALIDATION/reject")
                        .with(csrf()).session(session)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(Map.of("rejectComment", tooLongAfterTrim))))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code", equalTo("VALIDATION_ERROR")));
        assertUnchanged(reportRow("R-REJECT-VALIDATION"), "PENDING");

        String maximumComment = "x".repeat(1000);
        mockMvc.perform(post("/api/daily-reports/R-REJECT-VALIDATION/reject")
                        .with(csrf()).session(session)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(rejectJson("  " + maximumComment + "  ")))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.rejectComment", equalTo(maximumComment)));
        assertThat(reportRow("R-REJECT-VALIDATION").get("REJECT_COMMENT")).isEqualTo(maximumComment);
        mockMvc.perform(get("/api/daily-reports/R-REJECT-VALIDATION").session(session))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.rejectComment", equalTo(maximumComment)));
    }

    @Test
    void rtAprBe009ApproveRequiresAuthenticationMissingAndInvalidCsrfAndRolesWithoutChanges() throws Exception {
        seedReport(jdbcTemplate, "R-APPROVE-SECURITY", "U001", "E001", "山田 太郎",
                "G001", "第1開発グループ", LocalDate.of(2026, 6, 9), "PENDING");
        MockHttpSession session = loginAs(mockMvc, objectMapper, "manager001");
        MockHttpSession employeeSession = loginAs(mockMvc, objectMapper, "employee001");
        MockHttpSession adminSession = loginAs(mockMvc, objectMapper, "admin001");

        mockMvc.perform(post("/api/daily-reports/R-APPROVE-SECURITY/approve").with(csrf()))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code", equalTo("UNAUTHORIZED")));
        mockMvc.perform(post("/api/daily-reports/R-APPROVE-SECURITY/approve").session(session))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code", equalTo("FORBIDDEN")));
        mockMvc.perform(post("/api/daily-reports/R-APPROVE-SECURITY/approve")
                        .with(csrf().useInvalidToken()).session(session))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code", equalTo("FORBIDDEN")));
        mockMvc.perform(post("/api/daily-reports/R-APPROVE-SECURITY/approve")
                        .with(csrf()).session(employeeSession))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code", equalTo("FORBIDDEN")));
        mockMvc.perform(post("/api/daily-reports/R-APPROVE-SECURITY/approve")
                        .with(csrf()).session(adminSession))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code", equalTo("FORBIDDEN")));

        assertUnchanged(reportRow("R-APPROVE-SECURITY"), "PENDING");
    }

    @Test
    void rtAprBe010RejectRequiresAuthenticationMissingAndInvalidCsrfAndRolesWithoutChanges() throws Exception {
        seedReport(jdbcTemplate, "R-REJECT-SECURITY", "U001", "E001", "山田 太郎",
                "G001", "第1開発グループ", LocalDate.of(2026, 6, 10), "PENDING");
        MockHttpSession session = loginAs(mockMvc, objectMapper, "manager001");
        MockHttpSession employeeSession = loginAs(mockMvc, objectMapper, "employee001");
        MockHttpSession adminSession = loginAs(mockMvc, objectMapper, "admin001");

        mockMvc.perform(post("/api/daily-reports/R-REJECT-SECURITY/reject")
                        .with(csrf()).contentType(MediaType.APPLICATION_JSON).content(rejectJson("確認してください。")))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code", equalTo("UNAUTHORIZED")));
        mockMvc.perform(post("/api/daily-reports/R-REJECT-SECURITY/reject").session(session)
                        .contentType(MediaType.APPLICATION_JSON).content(rejectJson("確認してください。")))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code", equalTo("FORBIDDEN")));
        mockMvc.perform(post("/api/daily-reports/R-REJECT-SECURITY/reject").with(csrf().useInvalidToken()).session(session)
                        .contentType(MediaType.APPLICATION_JSON).content(rejectJson("確認してください。")))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code", equalTo("FORBIDDEN")));
        mockMvc.perform(post("/api/daily-reports/R-REJECT-SECURITY/reject").with(csrf()).session(employeeSession)
                        .contentType(MediaType.APPLICATION_JSON).content(rejectJson("確認してください。")))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code", equalTo("FORBIDDEN")));
        mockMvc.perform(post("/api/daily-reports/R-REJECT-SECURITY/reject").with(csrf()).session(adminSession)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(rejectJson("確認してください。")))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code", equalTo("FORBIDDEN")));

        assertUnchanged(reportRow("R-REJECT-SECURITY"), "PENDING");
    }

    private void seedOutsideEmployee() {
        seedUser(jdbcTemplate, "U099", "E099", "employee099", "他部署 社員", "EMPLOYEE", "G099", "他部署グループ");
    }

    private void seedOutsideManager() {
        seedUser(jdbcTemplate, "U099", "M099", "manager099", "担当外 上長", "MANAGER", "G099", "他部署グループ");
        jdbcTemplate.update("""
                UPDATE users
                SET password_hash = (SELECT password_hash FROM users WHERE user_id = 'U002')
                WHERE user_id = 'U099'
                """);
    }

    private void assertApprovedAuditVisible(MockHttpSession session) throws Exception {
        mockMvc.perform(get("/api/daily-reports/R-DETAIL-APPROVED").session(session))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.approvalStatus", equalTo("APPROVED")))
                .andExpect(jsonPath("$.approverId", equalTo("U002")))
                .andExpect(jsonPath("$.approverName", equalTo("佐藤 花子")))
                .andExpect(jsonPath("$.approvedAt", notNullValue()));
    }

    private void assertRejectedAuditVisible(MockHttpSession session) throws Exception {
        mockMvc.perform(get("/api/daily-reports/R-DETAIL-REJECTED").session(session))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.approvalStatus", equalTo("REJECTED")))
                .andExpect(jsonPath("$.rejectorId", equalTo("U002")))
                .andExpect(jsonPath("$.rejectorName", equalTo("佐藤 花子")))
                .andExpect(jsonPath("$.rejectedAt", notNullValue()))
                .andExpect(jsonPath("$.rejectComment", equalTo("監査情報を確認してください。")));
    }

    private void assertAuditIsNotLeakedToOutsideManager(String reportId, MockHttpSession session) throws Exception {
        mockMvc.perform(get("/api/daily-reports/" + reportId).session(session))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code", equalTo("FORBIDDEN")))
                .andExpect(jsonPath("$.approverId").doesNotExist())
                .andExpect(jsonPath("$.approvedAt").doesNotExist())
                .andExpect(jsonPath("$.rejectorId").doesNotExist())
                .andExpect(jsonPath("$.rejectedAt").doesNotExist())
                .andExpect(jsonPath("$.rejectComment").doesNotExist());
    }

    private String rejectJson(String comment) throws Exception {
        return objectMapper.writeValueAsString(Map.of("rejectComment", comment));
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

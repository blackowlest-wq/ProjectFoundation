package com.example.dailyreport.report;

import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.notNullValue;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.csrf;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.LocalDate;
import java.util.LinkedHashMap;
import java.util.List;
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
import org.springframework.test.web.servlet.MvcResult;

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Sql(statements = {
        "DELETE FROM daily_report_work_items",
        "DELETE FROM daily_reports"
}, executionPhase = Sql.ExecutionPhase.BEFORE_TEST_METHOD)
class DailyReportControllerTest {
    @Autowired
    MockMvc mockMvc;

    @Autowired
    ObjectMapper objectMapper;

    @Autowired
    JdbcTemplate jdbcTemplate;

    @Test
    void createWorkdayReportCalculatesMinutes() throws Exception {
        MockHttpSession session = loginAs("employee001");
        String reportId = createReportId(session, LocalDate.of(2026, 6, 1), 480);

        mockMvc.perform(get("/api/daily-reports/" + reportId).session(session))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.breakMinutes", equalTo(60)))
                .andExpect(jsonPath("$.workMinutes", equalTo(480)))
                .andExpect(jsonPath("$.regularWorkMinutes", equalTo(480)))
                .andExpect(jsonPath("$.totalWorkItemMinutes", equalTo(480)));
    }

    @Test
    void editDraftReportKeepsDraftStatus() throws Exception {
        MockHttpSession session = loginAs("employee001");
        String reportId = createReportId(session, LocalDate.of(2026, 6, 7), 480);

        mockMvc.perform(put("/api/daily-reports/" + reportId)
                        .with(csrf())
                        .session(session)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(reportJson(LocalDate.of(2026, 6, 7), "WORKDAY", "09:00", "18:00", 480, "updated")))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.approvalStatus", equalTo("DRAFT")));
    }

    @Test
    void submitDraftReportChangesToPending() throws Exception {
        MockHttpSession session = loginAs("employee001");
        String reportId = createReportId(session, LocalDate.of(2026, 6, 8), 480);

        mockMvc.perform(post("/api/daily-reports/" + reportId + "/submit").with(csrf()).session(session))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.approvalStatus", equalTo("PENDING")))
                .andExpect(jsonPath("$.submittedAt", notNullValue()));
    }

    @Test
    void pendingReportCannotBeEdited() throws Exception {
        MockHttpSession session = loginAs("employee001");
        String reportId = createReportId(session, LocalDate.of(2026, 6, 9), 480);
        mockMvc.perform(post("/api/daily-reports/" + reportId + "/submit").with(csrf()).session(session))
                .andExpect(status().isOk());

        mockMvc.perform(put("/api/daily-reports/" + reportId)
                        .with(csrf())
                        .session(session)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(reportJson(LocalDate.of(2026, 6, 1), "WORKDAY", "09:00", "18:00", 480, "blocked")))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code", equalTo("INVALID_STATUS")));
    }

    @Test
    void createRejectsDuplicateReportForSameEmployeeAndDate() throws Exception {
        MockHttpSession session = loginAs("employee001");
        createReport(session, LocalDate.of(2026, 6, 2), 480).andExpect(status().isCreated());

        createReport(session, LocalDate.of(2026, 6, 2), 480)
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code", equalTo("DUPLICATE_REPORT")));
    }

    @Test
    void createRejectsWorkItemTotalMismatch() throws Exception {
        MockHttpSession session = loginAs("employee001");

        createReport(session, LocalDate.of(2026, 6, 3), 479)
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code", equalTo("VALIDATION_ERROR")));
    }

    @Test
    void createAllowsHolidayWithoutWorkItemsAndPaidLeave() throws Exception {
        MockHttpSession session = loginAs("employee001");

        mockMvc.perform(post("/api/daily-reports")
                        .with(csrf())
                        .session(session)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(reportJson(LocalDate.of(2026, 6, 4), "HOLIDAY", null, null, 0, null)))
                .andExpect(status().isCreated());

        mockMvc.perform(post("/api/daily-reports")
                        .with(csrf())
                        .session(session)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(reportJson(LocalDate.of(2026, 6, 5), "PAID_LEAVE", null, null, 0, null)))
                .andExpect(status().isCreated());
    }

    @Test
    void managerCannotCreateEmployeeReport() throws Exception {
        MockHttpSession session = loginAs("manager001");

        createReport(session, LocalDate.of(2026, 6, 6), 480)
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code", equalTo("FORBIDDEN")));
    }

    @Test
    void createRequiresCsrfToken() throws Exception {
        MockHttpSession session = loginAs("employee001");

        mockMvc.perform(post("/api/daily-reports")
                        .session(session)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(reportJson(LocalDate.of(2026, 6, 10), "WORKDAY", "09:00", "18:00", 480, "remarks")))
                .andExpect(status().isForbidden());
    }

    @Test
    void protectedDailyReportApiRequiresLogin() throws Exception {
        mockMvc.perform(get("/api/master/projects"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void masterOptionsAreAvailableForLoggedInUser() throws Exception {
        MockHttpSession session = loginAs("employee001");

        mockMvc.perform(get("/api/master/projects").session(session))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].projectId", equalTo("P001")));

        mockMvc.perform(get("/api/master/holiday-types").session(session))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].holidayType", equalTo("WORKDAY")));
    }

    @Test
    void searchRequiresDateRange() throws Exception {
        MockHttpSession session = loginAs("employee001");

        mockMvc.perform(get("/api/daily-reports").session(session))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code", equalTo("VALIDATION_ERROR")));
    }

    @Test
    void searchRequiresLogin() throws Exception {
        mockMvc.perform(get("/api/daily-reports")
                        .param("dateFrom", "2026-06-01")
                        .param("dateTo", "2026-06-30"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void detailRequiresLogin() throws Exception {
        mockMvc.perform(get("/api/daily-reports/R-any"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void searchRejectsInvalidDateFormat() throws Exception {
        MockHttpSession session = loginAs("employee001");

        mockMvc.perform(get("/api/daily-reports")
                        .param("dateFrom", "invalid")
                        .param("dateTo", "2026-06-30")
                        .session(session))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code", equalTo("VALIDATION_ERROR")))
                .andExpect(jsonPath("$.details[0].field", equalTo("dateFrom")));
    }

    @Test
    void searchRejectsInvalidApprovalStatus() throws Exception {
        MockHttpSession session = loginAs("employee001");

        mockMvc.perform(get("/api/daily-reports")
                        .param("dateFrom", "2026-06-01")
                        .param("dateTo", "2026-06-30")
                        .param("status", "INVALID")
                        .session(session))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code", equalTo("VALIDATION_ERROR")))
                .andExpect(jsonPath("$.details[0].field", equalTo("status")));
    }

    @Test
    void searchRejectsTooWideDateRange() throws Exception {
        MockHttpSession session = loginAs("employee001");

        mockMvc.perform(get("/api/daily-reports")
                        .param("dateFrom", "2026-01-01")
                        .param("dateTo", "2027-01-03")
                        .session(session))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code", equalTo("VALIDATION_ERROR")))
                .andExpect(jsonPath("$.details[0].field", equalTo("dateTo")));
    }

    @Test
    void employeeSearchReturnsOnlyOwnReportsInDateRange() throws Exception {
        MockHttpSession session = loginAs("employee001");
        createReportId(session, LocalDate.of(2026, 6, 24), 480);
        seedUser("U099", "E099", "other001", "他部署 社員", "EMPLOYEE", "G099", "他部署グループ");
        seedReport("R-OTHER-001", "U099", "E099", "他部署 社員", "G099", "他部署グループ",
                LocalDate.of(2026, 6, 24), "PENDING");

        mockMvc.perform(get("/api/daily-reports")
                        .param("dateFrom", "2026-06-01")
                        .param("dateTo", "2026-06-30")
                        .session(session))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()", equalTo(1)))
                .andExpect(jsonPath("$[0].employeeId", equalTo("E001")));
    }

    @Test
    void employeeSearchIgnoresOtherEmployeeIdFilter() throws Exception {
        MockHttpSession session = loginAs("employee001");
        seedUser("U099", "E099", "other001", "他部署 社員", "EMPLOYEE", "G099", "他部署グループ");
        seedReport("R-OTHER-001", "U099", "E099", "他部署 社員", "G099", "他部署グループ",
                LocalDate.of(2026, 6, 24), "PENDING");

        mockMvc.perform(get("/api/daily-reports")
                        .param("dateFrom", "2026-06-01")
                        .param("dateTo", "2026-06-30")
                        .param("employeeId", "E099")
                        .session(session))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()", equalTo(0)));
    }

    @Test
    void managerSearchReturnsOnlyPermittedGroupReports() throws Exception {
        seedUser("U099", "E099", "other001", "他部署 社員", "EMPLOYEE", "G099", "他部署グループ");
        seedReport("R-G001-001", "U001", "E001", "山田 太郎", "G001", "第1開発グループ",
                LocalDate.of(2026, 6, 25), "PENDING");
        seedReport("R-G099-001", "U099", "E099", "他部署 社員", "G099", "他部署グループ",
                LocalDate.of(2026, 6, 25), "PENDING");
        MockHttpSession session = loginAs("manager001");

        mockMvc.perform(get("/api/daily-reports")
                        .param("dateFrom", "2026-06-01")
                        .param("dateTo", "2026-06-30")
                        .session(session))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()", equalTo(1)))
                .andExpect(jsonPath("$[0].groupId", equalTo("G001")));
    }

    @Test
    void managerSearchWithOutsideGroupFilterReturnsEmpty() throws Exception {
        seedUser("U099", "E099", "other001", "他部署 社員", "EMPLOYEE", "G099", "他部署グループ");
        seedReport("R-G001-001", "U001", "E001", "山田 太郎", "G001", "第1開発グループ",
                LocalDate.of(2026, 6, 25), "PENDING");
        seedReport("R-G099-001", "U099", "E099", "他部署 社員", "G099", "他部署グループ",
                LocalDate.of(2026, 6, 25), "PENDING");
        MockHttpSession session = loginAs("manager001");

        mockMvc.perform(get("/api/daily-reports")
                        .param("dateFrom", "2026-06-01")
                        .param("dateTo", "2026-06-30")
                        .param("groupId", "G099")
                        .session(session))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()", equalTo(0)));
    }

    @Test
    void adminSearchReturnsMultipleEmployeesAndCanFilterByGroupAndEmployee() throws Exception {
        seedUser("U099", "E099", "other001", "他部署 社員", "EMPLOYEE", "G099", "他部署グループ");
        seedReport("R-G001-001", "U001", "E001", "山田 太郎", "G001", "第1開発グループ",
                LocalDate.of(2026, 6, 25), "PENDING");
        seedReport("R-G099-001", "U099", "E099", "他部署 社員", "G099", "他部署グループ",
                LocalDate.of(2026, 6, 25), "PENDING");
        MockHttpSession session = loginAs("admin001");

        mockMvc.perform(get("/api/daily-reports")
                        .param("dateFrom", "2026-06-01")
                        .param("dateTo", "2026-06-30")
                        .session(session))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()", equalTo(2)));

        mockMvc.perform(get("/api/daily-reports")
                        .param("dateFrom", "2026-06-01")
                        .param("dateTo", "2026-06-30")
                        .param("groupId", "G099")
                        .param("employeeId", "E099")
                        .session(session))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()", equalTo(1)))
                .andExpect(jsonPath("$[0].reportId", equalTo("R-G099-001")));
    }

    @Test
    void searchReturnsReportsOrderedByDateAndEmployeeId() throws Exception {
        seedUser("U099", "E099", "other001", "他部署 社員", "EMPLOYEE", "G099", "他部署グループ");
        seedReport("R-SECOND-DAY", "U001", "E001", "山田 太郎", "G001", "第1開発グループ",
                LocalDate.of(2026, 6, 26), "PENDING");
        seedReport("R-FIRST-DAY-E099", "U099", "E099", "他部署 社員", "G099", "他部署グループ",
                LocalDate.of(2026, 6, 25), "PENDING");
        seedReport("R-FIRST-DAY-E001", "U001", "E001", "山田 太郎", "G001", "第1開発グループ",
                LocalDate.of(2026, 6, 25), "PENDING");
        MockHttpSession session = loginAs("admin001");

        mockMvc.perform(get("/api/daily-reports")
                        .param("dateFrom", "2026-06-01")
                        .param("dateTo", "2026-06-30")
                        .session(session))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].reportId", equalTo("R-FIRST-DAY-E001")))
                .andExpect(jsonPath("$[1].reportId", equalTo("R-FIRST-DAY-E099")))
                .andExpect(jsonPath("$[2].reportId", equalTo("R-SECOND-DAY")));
    }

    @Test
    void managerCanGetOnlyPermittedGroupReportDetail() throws Exception {
        seedUser("U099", "E099", "other001", "他部署 社員", "EMPLOYEE", "G099", "他部署グループ");
        seedReport("R-G001-001", "U001", "E001", "山田 太郎", "G001", "第1開発グループ",
                LocalDate.of(2026, 6, 25), "PENDING");
        seedReport("R-G099-001", "U099", "E099", "他部署 社員", "G099", "他部署グループ",
                LocalDate.of(2026, 6, 25), "PENDING");
        MockHttpSession session = loginAs("manager001");

        mockMvc.perform(get("/api/daily-reports/R-G001-001").session(session))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.groupId", equalTo("G001")));

        mockMvc.perform(get("/api/daily-reports/R-G099-001").session(session))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code", equalTo("FORBIDDEN")));
    }

    @Test
    void adminSearchCanFilterByStatusAndHolidayType() throws Exception {
        seedReport("R-DRAFT-001", "U001", "E001", "山田 太郎", "G001", "第1開発グループ",
                LocalDate.of(2026, 6, 26), "DRAFT");
        seedReport("R-PENDING-001", "U001", "E001", "山田 太郎", "G001", "第1開発グループ",
                LocalDate.of(2026, 6, 27), "PENDING");
        MockHttpSession session = loginAs("admin001");

        mockMvc.perform(get("/api/daily-reports")
                        .param("dateFrom", "2026-06-01")
                        .param("dateTo", "2026-06-30")
                        .param("status", "PENDING")
                        .param("holidayType", "WORKDAY")
                        .session(session))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()", equalTo(1)))
                .andExpect(jsonPath("$[0].reportId", equalTo("R-PENDING-001")))
                .andExpect(jsonPath("$[0].approvalStatus", equalTo("PENDING")));
    }

    @Test
    void getMissingReportReturnsNotFound() throws Exception {
        MockHttpSession session = loginAs("employee001");

        mockMvc.perform(get("/api/daily-reports/not-found").session(session))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code", equalTo("NOT_FOUND")));
    }

    @Test
    void updateMissingOwnReportReturnsForbidden() throws Exception {
        MockHttpSession session = loginAs("employee001");

        mockMvc.perform(put("/api/daily-reports/not-found")
                        .with(csrf())
                        .session(session)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(reportJson(LocalDate.of(2026, 6, 11), "WORKDAY", "09:00", "18:00", 480, "missing")))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code", equalTo("FORBIDDEN")));
    }

    @Test
    void submitPendingReportIsRejected() throws Exception {
        MockHttpSession session = loginAs("employee001");
        String reportId = createReportId(session, LocalDate.of(2026, 6, 12), 480);
        mockMvc.perform(post("/api/daily-reports/" + reportId + "/submit").with(csrf()).session(session))
                .andExpect(status().isOk());

        mockMvc.perform(post("/api/daily-reports/" + reportId + "/submit").with(csrf()).session(session))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code", equalTo("INVALID_STATUS")));
    }

    @Test
    void rejectedReportCanBeResubmitted() throws Exception {
        MockHttpSession session = loginAs("employee001");
        String reportId = createReportId(session, LocalDate.of(2026, 6, 13), 480);
        jdbcTemplate.update("UPDATE daily_reports SET approval_status = 'REJECTED' WHERE report_id = ?", reportId);

        mockMvc.perform(post("/api/daily-reports/" + reportId + "/resubmit").with(csrf()).session(session))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.approvalStatus", equalTo("PENDING")))
                .andExpect(jsonPath("$.submittedAt", notNullValue()));
    }

    @Test
    void resubmitDraftReportIsRejected() throws Exception {
        MockHttpSession session = loginAs("employee001");
        String reportId = createReportId(session, LocalDate.of(2026, 6, 14), 480);

        mockMvc.perform(post("/api/daily-reports/" + reportId + "/resubmit").with(csrf()).session(session))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code", equalTo("INVALID_STATUS")));
    }

    @Test
    void submitCorruptedStoredReportIsRejected() throws Exception {
        MockHttpSession session = loginAs("employee001");
        String reportId = createReportId(session, LocalDate.of(2026, 6, 15), 480);
        jdbcTemplate.update("UPDATE daily_reports SET work_minutes = 999 WHERE report_id = ?", reportId);

        mockMvc.perform(post("/api/daily-reports/" + reportId + "/submit").with(csrf()).session(session))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code", equalTo("VALIDATION_ERROR")));
    }

    @Test
    void createRejectsMissingHolidayType() throws Exception {
        MockHttpSession session = loginAs("employee001");
        Map<String, Object> request = new LinkedHashMap<>();
        request.put("reportDate", LocalDate.of(2026, 6, 16).toString());
        request.put("startTime", "09:00");
        request.put("endTime", "18:00");
        request.put("workItems", List.of(Map.of("projectId", "P001", "workCategoryId", "WC001", "workMinutes", 480)));

        mockMvc.perform(post("/api/daily-reports")
                        .with(csrf())
                        .session(session)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(request)))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code", equalTo("VALIDATION_ERROR")));
    }

    @Test
    void createRejectsInvalidTimeFormat() throws Exception {
        MockHttpSession session = loginAs("employee001");

        mockMvc.perform(post("/api/daily-reports")
                        .with(csrf())
                        .session(session)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(reportJson(LocalDate.of(2026, 6, 17), "WORKDAY", "9:00", "24:01", 480, "invalid")))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code", equalTo("VALIDATION_ERROR")));
    }

    @Test
    void createRejectsPaidLeaveWithWorkInput() throws Exception {
        MockHttpSession session = loginAs("employee001");

        mockMvc.perform(post("/api/daily-reports")
                        .with(csrf())
                        .session(session)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(reportJson(LocalDate.of(2026, 6, 18), "PAID_LEAVE", "09:00", "18:00", 480, "invalid")))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code", equalTo("VALIDATION_ERROR")));
    }

    @Test
    void createRejectsHolidayWithoutItemsButWithTimes() throws Exception {
        MockHttpSession session = loginAs("employee001");

        mockMvc.perform(post("/api/daily-reports")
                        .with(csrf())
                        .session(session)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(reportJson(LocalDate.of(2026, 6, 19), "HOLIDAY", "09:00", "18:00", 0, "invalid")))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code", equalTo("VALIDATION_ERROR")));
    }

    @Test
    void createRejectsWorkdayMissingTimesAndItems() throws Exception {
        MockHttpSession session = loginAs("employee001");

        mockMvc.perform(post("/api/daily-reports")
                        .with(csrf())
                        .session(session)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(reportJson(LocalDate.of(2026, 6, 20), "WORKDAY", null, null, 0, "invalid")))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code", equalTo("VALIDATION_ERROR")));
    }

    @Test
    void createRejectsEndTimeBeforeStartTime() throws Exception {
        MockHttpSession session = loginAs("employee001");

        mockMvc.perform(post("/api/daily-reports")
                        .with(csrf())
                        .session(session)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(reportJson(LocalDate.of(2026, 6, 21), "WORKDAY", "18:00", "09:00", 480, "invalid")))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code", equalTo("VALIDATION_ERROR")));
    }

    @Test
    void createRejectsBreakLongerThanElapsedTime() throws Exception {
        MockHttpSession session = loginAs("employee001");

        mockMvc.perform(post("/api/daily-reports")
                        .with(csrf())
                        .session(session)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(reportJson(LocalDate.of(2026, 6, 22), "WORKDAY", "12:00", "12:30", 1, "invalid")))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code", equalTo("VALIDATION_ERROR")));
    }

    @Test
    void holidayWithoutWorkItemsCanBeReadWithEmptyDurations() throws Exception {
        MockHttpSession session = loginAs("employee001");
        String responseBody = mockMvc.perform(post("/api/daily-reports")
                        .with(csrf())
                        .session(session)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(reportJson(LocalDate.of(2026, 6, 23), "HOLIDAY", null, null, 0, "holiday")))
                .andExpect(status().isCreated())
                .andReturn()
                .getResponse()
                .getContentAsString();
        String reportId = objectMapper.readTree(responseBody).get("reportId").asText();

        mockMvc.perform(get("/api/daily-reports/" + reportId).session(session))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.startTime").doesNotExist())
                .andExpect(jsonPath("$.workTimeDisplay", equalTo("0:00")));
    }

    private org.springframework.test.web.servlet.ResultActions createReport(
            MockHttpSession session, LocalDate date, int workMinutes) throws Exception {
        return mockMvc.perform(post("/api/daily-reports")
                .with(csrf())
                .session(session)
                .contentType(MediaType.APPLICATION_JSON)
                .content(reportJson(date, "WORKDAY", "09:00", "18:00", workMinutes, "remarks")));
    }

    private String createReportId(MockHttpSession session, LocalDate date, int workMinutes) throws Exception {
        String responseBody = createReport(session, date, workMinutes)
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.approvalStatus", equalTo("DRAFT")))
                .andReturn()
                .getResponse()
                .getContentAsString();
        return objectMapper.readTree(responseBody).get("reportId").asText();
    }

    private MockHttpSession loginAs(String loginId) throws Exception {
        MvcResult result = mockMvc.perform(post("/api/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(Map.of("loginId", loginId, "password", "password"))))
                .andExpect(status().isOk())
                .andReturn();
        return (MockHttpSession) result.getRequest().getSession(false);
    }

    private void seedUser(String userId, String employeeId, String loginId, String userName,
                          String role, String groupId, String groupName) {
        jdbcTemplate.update("""
                MERGE INTO users target
                USING (SELECT ? user_id, ? employee_id, ? login_id, ? user_name, ? user_role,
                              ? group_id, ? group_name FROM dual) source
                ON (target.user_id = source.user_id)
                WHEN MATCHED THEN UPDATE SET target.employee_id = source.employee_id,
                    target.login_id = source.login_id, target.user_name = source.user_name,
                    target.user_role = source.user_role, target.group_id = source.group_id,
                    target.group_name = source.group_name
                WHEN NOT MATCHED THEN INSERT (user_id, employee_id, login_id, password_hash, user_name,
                    user_role, group_id, group_name, break_type_id, break_type_name, work_time_type_id, work_time_type_name)
                VALUES (source.user_id, source.employee_id, source.login_id,
                    '$2a$10$123456789012345678901u12345678901234567890123456789012',
                    source.user_name, source.user_role, source.group_id, source.group_name,
                    'BT001', '標準休憩', 'WT001', '通常勤務')
                """, userId, employeeId, loginId, userName, role, groupId, groupName);
    }

    private void seedReport(String reportId, String employeeUserId, String employeeId, String employeeName,
                            String groupId, String groupName, LocalDate reportDate, String approvalStatus) {
        jdbcTemplate.update("""
                INSERT INTO daily_reports (
                    report_id, employee_user_id, employee_id, employee_name, group_id, group_name,
                    report_date, holiday_type, break_type_id, break_type_name, work_time_type_id, work_time_type_name,
                    start_time_minutes, end_time_minutes, break_minutes, work_minutes, regular_work_minutes,
                    overtime_work_minutes, night_work_minutes, remarks, approval_status
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, 'WORKDAY', 'BT001', '標準休憩', 'WT001', '通常勤務',
                    540, 1080, 60, 480, 480, 0, 0, '検索テスト', ?)
                """, reportId, employeeUserId, employeeId, employeeName, groupId, groupName, reportDate, approvalStatus);
    }

    private String reportJson(LocalDate reportDate, String holidayType, String startTime, String endTime,
                              int workMinutes, String remarks) throws Exception {
        List<Map<String, Object>> items = workMinutes > 0
                ? List.of(Map.of("projectId", "P001", "workCategoryId", "WC001", "workMinutes", workMinutes))
                : List.of();
        Map<String, Object> request = new LinkedHashMap<>();
        request.put("reportDate", reportDate.toString());
        request.put("holidayType", holidayType);
        request.put("startTime", startTime);
        request.put("endTime", endTime);
        request.put("remarks", remarks);
        request.put("workItems", items);
        return objectMapper.writeValueAsString(request);
    }
}

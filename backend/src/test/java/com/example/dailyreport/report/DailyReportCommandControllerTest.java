package com.example.dailyreport.report;

import static com.example.dailyreport.report.support.DailyReportTestSupport.*;
import static com.example.dailyreport.support.MockMvcTestSupport.loginAs;
import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.hasSize;
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

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Sql(statements = {
        "DELETE FROM daily_report_work_items",
        "DELETE FROM daily_reports"
}, executionPhase = Sql.ExecutionPhase.BEFORE_TEST_METHOD)
class DailyReportCommandControllerTest {
    @Autowired
    MockMvc mockMvc;

    @Autowired
    ObjectMapper objectMapper;

    @Autowired
    JdbcTemplate jdbcTemplate;

    @Test
    void createWorkdayReportCalculatesMinutes() throws Exception {
        MockHttpSession session = loginAs(mockMvc, objectMapper, "employee001");
        String reportId = createReportId(mockMvc, objectMapper, session, LocalDate.of(2026, 6, 1), 480);

        mockMvc.perform(get("/api/daily-reports/" + reportId).session(session))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.breakMinutes", equalTo(60)))
                .andExpect(jsonPath("$.workMinutes", equalTo(480)))
                .andExpect(jsonPath("$.regularWorkMinutes", equalTo(480)))
                .andExpect(jsonPath("$.totalWorkItemMinutes", equalTo(480)));
    }

    @Test
    void newReportSnapshotsCurrentGroupMasterName() throws Exception {
        jdbcTemplate.update("UPDATE groups SET group_name = ? WHERE group_id = ?", "第1開発グループ_更新", "G001");
        try {
            MockHttpSession session = loginAs(mockMvc, objectMapper, "employee001");
            String reportId = createReportId(mockMvc, objectMapper, session, LocalDate.of(2026, 6, 1), 480);

            mockMvc.perform(get("/api/daily-reports/" + reportId).session(session))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.groupName", equalTo("第1開発グループ_更新")));
        } finally {
            jdbcTemplate.update("UPDATE groups SET group_name = ? WHERE group_id = ?", "第1開発グループ", "G001");
        }
    }

    @Test
    void createWorkdayReportReturnsOvertimeAndNightMinutes() throws Exception {
        MockHttpSession session = loginAs(mockMvc, objectMapper, "employee002");

        String responseBody = mockMvc.perform(post("/api/daily-reports")
                        .with(csrf())
                        .session(session)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(reportJson(objectMapper, LocalDate.of(2026, 7, 3), "WORKDAY",
                                "09:00", "23:00", 765, "overtime and night")))
                .andExpect(status().isCreated())
                .andReturn()
                .getResponse()
                .getContentAsString();
        String reportId = objectMapper.readTree(responseBody).get("reportId").asText();

        mockMvc.perform(get("/api/daily-reports/" + reportId).session(session))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.workMinutes", equalTo(765)))
                .andExpect(jsonPath("$.regularWorkMinutes", equalTo(450)))
                .andExpect(jsonPath("$.overtimeWorkMinutes", equalTo(255)))
                .andExpect(jsonPath("$.nightWorkMinutes", equalTo(60)))
                .andExpect(jsonPath("$.overtimeWorkTimeDisplay", equalTo("4:15")))
                .andExpect(jsonPath("$.nightWorkTimeDisplay", equalTo("1:00")));
    }

    @Test
    void editDraftReportKeepsDraftStatus() throws Exception {
        MockHttpSession session = loginAs(mockMvc, objectMapper, "employee001");
        String reportId = createReportId(mockMvc, objectMapper, session, LocalDate.of(2026, 6, 7), 480);

        mockMvc.perform(put("/api/daily-reports/" + reportId)
                        .with(csrf())
                        .session(session)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(reportJson(objectMapper, LocalDate.of(2026, 6, 7), "WORKDAY", "09:00", "18:00", 480, "updated")))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.approvalStatus", equalTo("DRAFT")));
    }

    @Test
    void pendingReportCannotBeEdited() throws Exception {
        MockHttpSession session = loginAs(mockMvc, objectMapper, "employee001");
        String reportId = createReportId(mockMvc, objectMapper, session, LocalDate.of(2026, 6, 9), 480);
        mockMvc.perform(post("/api/daily-reports/" + reportId + "/submit").with(csrf()).session(session))
                .andExpect(status().isOk());

        mockMvc.perform(put("/api/daily-reports/" + reportId)
                        .with(csrf())
                        .session(session)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(reportJson(objectMapper, LocalDate.of(2026, 6, 1), "WORKDAY", "09:00", "18:00", 480, "blocked")))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code", equalTo("INVALID_STATUS")));
    }

    @Test
    void createRejectsDuplicateReportForSameEmployeeAndDate() throws Exception {
        MockHttpSession session = loginAs(mockMvc, objectMapper, "employee001");
        createReport(mockMvc, objectMapper, session, LocalDate.of(2026, 6, 2), 480).andExpect(status().isCreated());

        createReport(mockMvc, objectMapper, session, LocalDate.of(2026, 6, 2), 480)
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code", equalTo("DUPLICATE_REPORT")));
    }

    @Test
    void createRejectsWorkItemTotalMismatch() throws Exception {
        MockHttpSession session = loginAs(mockMvc, objectMapper, "employee001");

        createReport(mockMvc, objectMapper, session, LocalDate.of(2026, 6, 3), 479)
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code", equalTo("VALIDATION_ERROR")));
    }

    @Test
    void createAllowsHolidayWithoutWorkItemsAndPaidLeave() throws Exception {
        MockHttpSession session = loginAs(mockMvc, objectMapper, "employee001");

        mockMvc.perform(post("/api/daily-reports")
                        .with(csrf())
                        .session(session)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(reportJson(objectMapper, LocalDate.of(2026, 6, 4), "HOLIDAY", null, null, 0, null)))
                .andExpect(status().isCreated());

        mockMvc.perform(post("/api/daily-reports")
                        .with(csrf())
                        .session(session)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(reportJson(objectMapper, LocalDate.of(2026, 6, 5), "PAID_LEAVE", null, null, 0, null)))
                .andExpect(status().isCreated());
    }

    @Test
    void managerCannotCreateEmployeeReport() throws Exception {
        MockHttpSession session = loginAs(mockMvc, objectMapper, "manager001");

        createReport(mockMvc, objectMapper, session, LocalDate.of(2026, 6, 6), 480)
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code", equalTo("FORBIDDEN")));
    }

    @Test
    void createRequiresCsrfToken() throws Exception {
        MockHttpSession session = loginAs(mockMvc, objectMapper, "employee001");

        mockMvc.perform(post("/api/daily-reports")
                        .session(session)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(reportJson(objectMapper, LocalDate.of(2026, 6, 10), "WORKDAY", "09:00", "18:00", 480, "remarks")))
                .andExpect(status().isForbidden());
    }

    @Test
    void updateMissingOwnReportReturnsForbidden() throws Exception {
        MockHttpSession session = loginAs(mockMvc, objectMapper, "employee001");

        mockMvc.perform(put("/api/daily-reports/not-found")
                        .with(csrf())
                        .session(session)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(reportJson(objectMapper, LocalDate.of(2026, 6, 11), "WORKDAY", "09:00", "18:00", 480, "missing")))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code", equalTo("FORBIDDEN")));
    }

    @Test
    void createRejectsMissingHolidayType() throws Exception {
        MockHttpSession session = loginAs(mockMvc, objectMapper, "employee001");
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
    void createRejectsNullWorkItemAsValidationError() throws Exception {
        MockHttpSession session = loginAs(mockMvc, objectMapper, "employee001");
        Map<String, Object> request = new LinkedHashMap<>();
        request.put("reportDate", LocalDate.of(2026, 6, 30).plusDays(1).toString());
        request.put("holidayType", "WORKDAY");
        request.put("startTime", "09:00");
        request.put("endTime", "18:00");
        request.put("workItems", java.util.Collections.singletonList(null));

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
        MockHttpSession session = loginAs(mockMvc, objectMapper, "employee001");

        mockMvc.perform(post("/api/daily-reports")
                        .with(csrf())
                        .session(session)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(reportJson(objectMapper, LocalDate.of(2026, 6, 17), "WORKDAY", "9:00", "24:01", 480, "invalid")))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code", equalTo("VALIDATION_ERROR")));
    }

    @Test
    void createRejectsPaidLeaveWithWorkInput() throws Exception {
        MockHttpSession session = loginAs(mockMvc, objectMapper, "employee001");

        mockMvc.perform(post("/api/daily-reports")
                        .with(csrf())
                        .session(session)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(reportJson(objectMapper, LocalDate.of(2026, 6, 18), "PAID_LEAVE", "09:00", "18:00", 480, "invalid")))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code", equalTo("VALIDATION_ERROR")));
    }

    @Test
    void createRejectsHolidayWithoutItemsButWithTimes() throws Exception {
        MockHttpSession session = loginAs(mockMvc, objectMapper, "employee001");

        mockMvc.perform(post("/api/daily-reports")
                        .with(csrf())
                        .session(session)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(reportJson(objectMapper, LocalDate.of(2026, 6, 19), "HOLIDAY", "09:00", "18:00", 0, "invalid")))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code", equalTo("VALIDATION_ERROR")));
    }

    @Test
    void createRejectsWorkdayMissingTimesAndItems() throws Exception {
        MockHttpSession session = loginAs(mockMvc, objectMapper, "employee001");

        mockMvc.perform(post("/api/daily-reports")
                        .with(csrf())
                        .session(session)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(reportJson(objectMapper, LocalDate.of(2026, 6, 20), "WORKDAY", null, null, 0, "invalid")))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code", equalTo("VALIDATION_ERROR")));
    }

    @Test
    void createRejectsEndTimeBeforeStartTime() throws Exception {
        MockHttpSession session = loginAs(mockMvc, objectMapper, "employee001");

        mockMvc.perform(post("/api/daily-reports")
                        .with(csrf())
                        .session(session)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(reportJson(objectMapper, LocalDate.of(2026, 6, 21), "WORKDAY", "18:00", "09:00", 480, "invalid")))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code", equalTo("VALIDATION_ERROR")));
    }

    @Test
    void createRejectsBreakLongerThanElapsedTime() throws Exception {
        MockHttpSession session = loginAs(mockMvc, objectMapper, "employee001");

        mockMvc.perform(post("/api/daily-reports")
                        .with(csrf())
                        .session(session)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(reportJson(objectMapper, LocalDate.of(2026, 6, 22), "WORKDAY", "12:00", "12:30", 1, "invalid")))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code", equalTo("VALIDATION_ERROR")));
    }

    @Test
    void holidayWithoutWorkItemsCanBeReadWithEmptyDurations() throws Exception {
        MockHttpSession session = loginAs(mockMvc, objectMapper, "employee001");
        String responseBody = mockMvc.perform(post("/api/daily-reports")
                        .with(csrf())
                        .session(session)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(reportJson(objectMapper, LocalDate.of(2026, 6, 23), "HOLIDAY", null, null, 0, "holiday")))
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

    @Test
    void createAllowsMultipleWorkItemsAndPreservesOrder() throws Exception {
        MockHttpSession session = loginAs(mockMvc, objectMapper, "employee001");
        String responseBody = mockMvc.perform(post("/api/daily-reports")
                        .with(csrf())
                        .session(session)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(reportJsonWithItems(objectMapper, LocalDate.of(2026, 6, 24), "WORKDAY",
                                "09:00", "18:00", "multiple", List.of(
                                        Map.of("projectId", "P001", "workCategoryId", "WC001", "workMinutes", 240),
                                        Map.of("projectId", "P002", "workCategoryId", "WC002", "workMinutes", 240)))))
                .andExpect(status().isCreated())
                .andReturn()
                .getResponse()
                .getContentAsString();
        String reportId = objectMapper.readTree(responseBody).get("reportId").asText();

        mockMvc.perform(get("/api/daily-reports/" + reportId).session(session))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.workItems", hasSize(2)))
                .andExpect(jsonPath("$.workItems[0].projectId", equalTo("P001")))
                .andExpect(jsonPath("$.workItems[0].workCategoryId", equalTo("WC001")))
                .andExpect(jsonPath("$.workItems[1].projectId", equalTo("P002")))
                .andExpect(jsonPath("$.workItems[1].workCategoryId", equalTo("WC002")))
                .andExpect(jsonPath("$.totalWorkItemMinutes", equalTo(480)));
    }

    @Test
    void createAllowsOneMinuteWorkItem() throws Exception {
        MockHttpSession session = loginAs(mockMvc, objectMapper, "employee001");

        String responseBody = mockMvc.perform(post("/api/daily-reports")
                        .with(csrf())
                        .session(session)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(reportJson(objectMapper, LocalDate.of(2026, 6, 25), "HOLIDAY", "09:00", "09:01", 1, "one minute")))
                .andExpect(status().isCreated())
                .andReturn()
                .getResponse()
                .getContentAsString();
        String reportId = objectMapper.readTree(responseBody).get("reportId").asText();

        mockMvc.perform(get("/api/daily-reports/" + reportId).session(session))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.workMinutes", equalTo(1)))
                .andExpect(jsonPath("$.totalWorkItemMinutes", equalTo(1)))
                .andExpect(jsonPath("$.approvalStatus", equalTo("DRAFT")));
    }

    @Test
    void createAllowsHolidayWithWorkItems() throws Exception {
        MockHttpSession session = loginAs(mockMvc, objectMapper, "employee001");

        String responseBody = mockMvc.perform(post("/api/daily-reports")
                        .with(csrf())
                        .session(session)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(reportJson(objectMapper, LocalDate.of(2026, 6, 26), "HOLIDAY", "09:00", "12:00", 180, "holiday work")))
                .andExpect(status().isCreated())
                .andReturn()
                .getResponse()
                .getContentAsString();
        String reportId = objectMapper.readTree(responseBody).get("reportId").asText();

        mockMvc.perform(get("/api/daily-reports/" + reportId).session(session))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.holidayType", equalTo("HOLIDAY")))
                .andExpect(jsonPath("$.workMinutes", equalTo(180)))
                .andExpect(jsonPath("$.totalWorkItemMinutes", equalTo(180)));
    }

    @Test
    void createAllowsAmOffWorkdayInput() throws Exception {
        MockHttpSession session = loginAs(mockMvc, objectMapper, "employee001");

        String responseBody = mockMvc.perform(post("/api/daily-reports")
                        .with(csrf())
                        .session(session)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(reportJson(objectMapper, LocalDate.of(2026, 6, 27), "AM_OFF", "09:00", "18:00", 480, "am off")))
                .andExpect(status().isCreated())
                .andReturn()
                .getResponse()
                .getContentAsString();
        String reportId = objectMapper.readTree(responseBody).get("reportId").asText();

        mockMvc.perform(get("/api/daily-reports/" + reportId).session(session))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.holidayType", equalTo("AM_OFF")))
                .andExpect(jsonPath("$.workMinutes", equalTo(480)))
                .andExpect(jsonPath("$.totalWorkItemMinutes", equalTo(480)));
    }

    @Test
    void createAllowsPmOffWorkdayInput() throws Exception {
        MockHttpSession session = loginAs(mockMvc, objectMapper, "employee001");

        String responseBody = mockMvc.perform(post("/api/daily-reports")
                        .with(csrf())
                        .session(session)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(reportJson(objectMapper, LocalDate.of(2026, 6, 28), "PM_OFF", "09:00", "18:00", 480, "pm off")))
                .andExpect(status().isCreated())
                .andReturn()
                .getResponse()
                .getContentAsString();
        String reportId = objectMapper.readTree(responseBody).get("reportId").asText();

        mockMvc.perform(get("/api/daily-reports/" + reportId).session(session))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.holidayType", equalTo("PM_OFF")))
                .andExpect(jsonPath("$.workMinutes", equalTo(480)))
                .andExpect(jsonPath("$.totalWorkItemMinutes", equalTo(480)));
    }

    @Test
    void createUsesAuthenticatedSecondaryEmployeeSnapshot() throws Exception {
        MockHttpSession session = loginAs(mockMvc, objectMapper, "employee002");

        String responseBody = mockMvc.perform(post("/api/daily-reports")
                        .with(csrf())
                        .session(session)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(reportJson(objectMapper, LocalDate.of(2026, 6, 29), "WORKDAY", "09:00", "17:30", 450, "secondary")))
                .andExpect(status().isCreated())
                .andReturn()
                .getResponse()
                .getContentAsString();
        String reportId = objectMapper.readTree(responseBody).get("reportId").asText();

        mockMvc.perform(get("/api/daily-reports/" + reportId).session(session))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.employeeId", equalTo("E002")))
                .andExpect(jsonPath("$.employeeName", equalTo("高橋 次郎")))
                .andExpect(jsonPath("$.groupId", equalTo("G002")))
                .andExpect(jsonPath("$.breakTypeId", equalTo("BT002")))
                .andExpect(jsonPath("$.workTimeTypeId", equalTo("WT002")));
    }

    @Test
    void createCannotChangeOwnerWithClientEmployeeFields() throws Exception {
        MockHttpSession session = loginAs(mockMvc, objectMapper, "employee002");
        Map<String, Object> request = new LinkedHashMap<>();
        request.put("reportDate", LocalDate.of(2026, 6, 30).toString());
        request.put("holidayType", "WORKDAY");
        request.put("startTime", "09:00");
        request.put("endTime", "17:30");
        request.put("remarks", "client owner attempt");
        request.put("employeeUserId", "U001");
        request.put("employeeId", "E001");
        request.put("employeeName", "山田 太郎");
        request.put("workItems", List.of(Map.of("projectId", "P001", "workCategoryId", "WC001", "workMinutes", 450)));

        String responseBody = mockMvc.perform(post("/api/daily-reports")
                        .with(csrf())
                        .session(session)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(request)))
                .andExpect(status().isCreated())
                .andReturn()
                .getResponse()
                .getContentAsString();
        String reportId = objectMapper.readTree(responseBody).get("reportId").asText();

        mockMvc.perform(get("/api/daily-reports/" + reportId).session(session))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.employeeId", equalTo("E002")))
                .andExpect(jsonPath("$.employeeName", equalTo("高橋 次郎")));
    }
}

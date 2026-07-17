package com.example.dailyreport.report;

import static com.example.dailyreport.report.support.DailyReportTestSupport.*;
import static com.example.dailyreport.support.MockMvcTestSupport.loginAs;
import static org.hamcrest.Matchers.equalTo;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
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

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Sql(statements = {
        "DELETE FROM daily_report_work_items",
        "DELETE FROM daily_reports"
}, executionPhase = Sql.ExecutionPhase.BEFORE_TEST_METHOD)
class DailyReportSearchControllerTest {
    @Autowired
    MockMvc mockMvc;

    @Autowired
    ObjectMapper objectMapper;

    @Autowired
    JdbcTemplate jdbcTemplate;

    @Test
    void searchRequiresDateRange() throws Exception {
        MockHttpSession session = loginAs(mockMvc, objectMapper, "employee001");

        mockMvc.perform(get("/api/daily-reports").session(session))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code", equalTo("VALIDATION_ERROR")));
    }

    @Test
    void searchRejectsMissingStartDate() throws Exception {
        MockHttpSession session = loginAs(mockMvc, objectMapper, "employee001");

        mockMvc.perform(get("/api/daily-reports").param("dateTo", "2026-06-30").session(session))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.details[0].field", equalTo("dateFrom")));
    }

    @Test
    void searchRejectsMissingEndDate() throws Exception {
        MockHttpSession session = loginAs(mockMvc, objectMapper, "employee001");

        mockMvc.perform(get("/api/daily-reports").param("dateFrom", "2026-06-01").session(session))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.details[0].field", equalTo("dateTo")));
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
        MockHttpSession session = loginAs(mockMvc, objectMapper, "employee001");

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
        MockHttpSession session = loginAs(mockMvc, objectMapper, "employee001");

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
        MockHttpSession session = loginAs(mockMvc, objectMapper, "employee001");

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
        MockHttpSession session = loginAs(mockMvc, objectMapper, "employee001");
        createReportId(mockMvc, objectMapper, session, LocalDate.of(2026, 6, 24), 480);
        seedUser(jdbcTemplate, "U099", "E099", "other001", "他部署 社員", "EMPLOYEE", "G099", "他部署グループ");
        seedReport(jdbcTemplate, "R-OTHER-001", "U099", "E099", "他部署 社員", "G099", "他部署グループ",
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
        MockHttpSession session = loginAs(mockMvc, objectMapper, "employee001");
        seedUser(jdbcTemplate, "U099", "E099", "other001", "他部署 社員", "EMPLOYEE", "G099", "他部署グループ");
        seedReport(jdbcTemplate, "R-OTHER-001", "U099", "E099", "他部署 社員", "G099", "他部署グループ",
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
        seedUser(jdbcTemplate, "U099", "E099", "other001", "他部署 社員", "EMPLOYEE", "G099", "他部署グループ");
        seedReport(jdbcTemplate, "R-G001-001", "U001", "E001", "山田 太郎", "G001", "第1開発グループ",
                LocalDate.of(2026, 6, 25), "PENDING");
        seedReport(jdbcTemplate, "R-G099-001", "U099", "E099", "他部署 社員", "G099", "他部署グループ",
                LocalDate.of(2026, 6, 25), "PENDING");
        MockHttpSession session = loginAs(mockMvc, objectMapper, "manager001");

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
        seedUser(jdbcTemplate, "U099", "E099", "other001", "他部署 社員", "EMPLOYEE", "G099", "他部署グループ");
        seedReport(jdbcTemplate, "R-G001-001", "U001", "E001", "山田 太郎", "G001", "第1開発グループ",
                LocalDate.of(2026, 6, 25), "PENDING");
        seedReport(jdbcTemplate, "R-G099-001", "U099", "E099", "他部署 社員", "G099", "他部署グループ",
                LocalDate.of(2026, 6, 25), "PENDING");
        MockHttpSession session = loginAs(mockMvc, objectMapper, "manager001");

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
        seedUser(jdbcTemplate, "U099", "E099", "other001", "他部署 社員", "EMPLOYEE", "G099", "他部署グループ");
        seedReport(jdbcTemplate, "R-G001-001", "U001", "E001", "山田 太郎", "G001", "第1開発グループ",
                LocalDate.of(2026, 6, 25), "PENDING");
        seedReport(jdbcTemplate, "R-G099-001", "U099", "E099", "他部署 社員", "G099", "他部署グループ",
                LocalDate.of(2026, 6, 25), "PENDING");
        MockHttpSession session = loginAs(mockMvc, objectMapper, "admin001");

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
        seedUser(jdbcTemplate, "U099", "E099", "other001", "他部署 社員", "EMPLOYEE", "G099", "他部署グループ");
        seedReport(jdbcTemplate, "R-SECOND-DAY", "U001", "E001", "山田 太郎", "G001", "第1開発グループ",
                LocalDate.of(2026, 6, 26), "PENDING");
        seedReport(jdbcTemplate, "R-FIRST-DAY-E099", "U099", "E099", "他部署 社員", "G099", "他部署グループ",
                LocalDate.of(2026, 6, 25), "PENDING");
        seedReport(jdbcTemplate, "R-FIRST-DAY-E001", "U001", "E001", "山田 太郎", "G001", "第1開発グループ",
                LocalDate.of(2026, 6, 25), "PENDING");
        MockHttpSession session = loginAs(mockMvc, objectMapper, "admin001");

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
        seedUser(jdbcTemplate, "U099", "E099", "other001", "他部署 社員", "EMPLOYEE", "G099", "他部署グループ");
        seedReport(jdbcTemplate, "R-G001-001", "U001", "E001", "山田 太郎", "G001", "第1開発グループ",
                LocalDate.of(2026, 6, 25), "PENDING");
        seedReport(jdbcTemplate, "R-G099-001", "U099", "E099", "他部署 社員", "G099", "他部署グループ",
                LocalDate.of(2026, 6, 25), "PENDING");
        MockHttpSession session = loginAs(mockMvc, objectMapper, "manager001");

        mockMvc.perform(get("/api/daily-reports/R-G001-001").session(session))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.groupId", equalTo("G001")));

        mockMvc.perform(get("/api/daily-reports/R-G099-001").session(session))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code", equalTo("FORBIDDEN")));
    }

    @Test
    void adminSearchCanFilterByStatusAndHolidayType() throws Exception {
        seedReport(jdbcTemplate, "R-DRAFT-001", "U001", "E001", "山田 太郎", "G001", "第1開発グループ",
                LocalDate.of(2026, 6, 26), "DRAFT");
        seedReport(jdbcTemplate, "R-PENDING-001", "U001", "E001", "山田 太郎", "G001", "第1開発グループ",
                LocalDate.of(2026, 6, 27), "PENDING");
        MockHttpSession session = loginAs(mockMvc, objectMapper, "admin001");

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
        MockHttpSession session = loginAs(mockMvc, objectMapper, "employee001");

        mockMvc.perform(get("/api/daily-reports/not-found").session(session))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code", equalTo("NOT_FOUND")));
    }
}

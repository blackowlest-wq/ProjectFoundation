package com.example.dailyreport.report;

import static com.example.dailyreport.report.support.DailyReportTestSupport.createReportId;
import static com.example.dailyreport.support.MockMvcTestSupport.loginAs;
import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.notNullValue;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.csrf;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
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
class DailyReportSubmissionControllerTest {
    @Autowired
    MockMvc mockMvc;

    @Autowired
    ObjectMapper objectMapper;

    @Autowired
    JdbcTemplate jdbcTemplate;

    @Test
    void submitDraftReportChangesToPending() throws Exception {
        MockHttpSession session = loginAs(mockMvc, objectMapper, "employee001");
        String reportId = createReportId(mockMvc, objectMapper, session, LocalDate.of(2026, 6, 8), 480);

        mockMvc.perform(post("/api/daily-reports/" + reportId + "/submit").with(csrf()).session(session))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.approvalStatus", equalTo("PENDING")))
                .andExpect(jsonPath("$.submittedAt", notNullValue()));
    }

    @Test
    void submitPendingReportIsRejected() throws Exception {
        MockHttpSession session = loginAs(mockMvc, objectMapper, "employee001");
        String reportId = createReportId(mockMvc, objectMapper, session, LocalDate.of(2026, 6, 12), 480);
        mockMvc.perform(post("/api/daily-reports/" + reportId + "/submit").with(csrf()).session(session))
                .andExpect(status().isOk());

        mockMvc.perform(post("/api/daily-reports/" + reportId + "/submit").with(csrf()).session(session))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code", equalTo("INVALID_STATUS")));
    }

    @Test
    void rejectedReportCanBeResubmitted() throws Exception {
        MockHttpSession session = loginAs(mockMvc, objectMapper, "employee001");
        String reportId = createReportId(mockMvc, objectMapper, session, LocalDate.of(2026, 6, 13), 480);
        jdbcTemplate.update("UPDATE daily_reports SET approval_status = 'REJECTED' WHERE report_id = ?", reportId);

        mockMvc.perform(post("/api/daily-reports/" + reportId + "/resubmit").with(csrf()).session(session))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.approvalStatus", equalTo("PENDING")))
                .andExpect(jsonPath("$.submittedAt", notNullValue()));
    }

    @Test
    void resubmitDraftReportIsRejected() throws Exception {
        MockHttpSession session = loginAs(mockMvc, objectMapper, "employee001");
        String reportId = createReportId(mockMvc, objectMapper, session, LocalDate.of(2026, 6, 14), 480);

        mockMvc.perform(post("/api/daily-reports/" + reportId + "/resubmit").with(csrf()).session(session))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code", equalTo("INVALID_STATUS")));
    }

    @Test
    void submitCorruptedStoredReportIsRejected() throws Exception {
        MockHttpSession session = loginAs(mockMvc, objectMapper, "employee001");
        String reportId = createReportId(mockMvc, objectMapper, session, LocalDate.of(2026, 6, 15), 480);
        jdbcTemplate.update("UPDATE daily_reports SET work_minutes = 999 WHERE report_id = ?", reportId);

        mockMvc.perform(post("/api/daily-reports/" + reportId + "/submit").with(csrf()).session(session))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code", equalTo("VALIDATION_ERROR")));
    }
}

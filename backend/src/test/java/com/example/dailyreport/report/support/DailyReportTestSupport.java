package com.example.dailyreport.report.support;

import static org.hamcrest.Matchers.equalTo;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.csrf;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.mock.web.MockHttpSession;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;

public final class DailyReportTestSupport {
    private DailyReportTestSupport() {
    }

    public static ResultActions createReport(MockMvc mockMvc, ObjectMapper objectMapper,
            MockHttpSession session, LocalDate date, int workMinutes) throws Exception {
        return mockMvc.perform(post("/api/daily-reports")
                .with(csrf())
                .session(session)
                .contentType(MediaType.APPLICATION_JSON)
                .content(reportJson(objectMapper, date, "WORKDAY", "09:00", "18:00", workMinutes, "remarks")));
    }

    public static String createReportId(MockMvc mockMvc, ObjectMapper objectMapper,
            MockHttpSession session, LocalDate date, int workMinutes) throws Exception {
        String responseBody = createReport(mockMvc, objectMapper, session, date, workMinutes)
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.approvalStatus", equalTo("DRAFT")))
                .andReturn()
                .getResponse()
                .getContentAsString();
        return objectMapper.readTree(responseBody).get("reportId").asText();
    }

    public static void seedUser(JdbcTemplate jdbcTemplate, String userId, String employeeId, String loginId,
            String userName, String role, String groupId, String groupName) {
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

    public static void seedReport(JdbcTemplate jdbcTemplate, String reportId, String employeeUserId, String employeeId,
            String employeeName, String groupId, String groupName, LocalDate reportDate, String approvalStatus) {
        boolean isApproved = "APPROVED".equals(approvalStatus);
        boolean isRejected = "REJECTED".equals(approvalStatus);
        OffsetDateTime approvedAt = isApproved ? OffsetDateTime.parse("2026-06-01T09:30:00+09:00") : null;
        OffsetDateTime rejectedAt = isRejected ? OffsetDateTime.parse("2026-06-01T10:30:00+09:00") : null;
        jdbcTemplate.update("""
                INSERT INTO daily_reports (
                    report_id, employee_user_id, employee_id, employee_name, group_id, group_name,
                    report_date, holiday_type, break_type_id, break_type_name, work_time_type_id, work_time_type_name,
                    start_time_minutes, end_time_minutes, break_minutes, work_minutes, regular_work_minutes,
                    overtime_work_minutes, night_work_minutes, remarks, approval_status,
                    approver_user_id, approver_name, approved_at,
                    rejector_user_id, rejector_name, rejected_at, reject_comment
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, 'WORKDAY', 'BT001', '標準休憩', 'WT001', '通常勤務',
                    540, 1080, 60, 480, 480, 0, 0, '検索テスト', ?,
                    ?, ?, ?, ?, ?, ?, ?)
                """, reportId, employeeUserId, employeeId, employeeName, groupId, groupName, reportDate, approvalStatus,
                isApproved ? "U002" : null, isApproved ? "佐藤 花子" : null, approvedAt,
                isRejected ? "U002" : null, isRejected ? "佐藤 花子" : null, rejectedAt,
                isRejected ? "事前に差し戻したコメントです。" : null);
    }

    public static String reportJson(ObjectMapper objectMapper, LocalDate reportDate, String holidayType,
            String startTime, String endTime, int workMinutes, String remarks) throws Exception {
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

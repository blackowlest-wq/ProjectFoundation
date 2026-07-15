package com.example.dailyreport.observability;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.example.dailyreport.auth.AppUser;
import com.example.dailyreport.auth.AuthController;
import com.example.dailyreport.auth.AuthenticatedUser;
import com.example.dailyreport.auth.LoginRequest;
import com.example.dailyreport.auth.Role;
import com.example.dailyreport.report.DailyReportCommandService;
import com.example.dailyreport.report.DailyReportSubmissionService;
import com.example.dailyreport.report.controller.DailyReportCommandController;
import com.example.dailyreport.report.controller.DailyReportSubmissionController;
import com.example.dailyreport.report.dto.DailyReportRequest;
import com.example.dailyreport.report.dto.DailyReportSummaryResponse;
import com.example.dailyreport.report.dto.SubmitResponse;
import java.time.OffsetDateTime;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.springframework.boot.test.system.CapturedOutput;
import org.springframework.boot.test.system.OutputCaptureExtension;
import org.springframework.http.ResponseEntity;
import org.springframework.security.authentication.AuthenticationManager;
import org.springframework.security.core.Authentication;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;

import com.example.dailyreport.workflow.ApprovalStatus;

@ExtendWith(OutputCaptureExtension.class)
class BusinessEventLoggingTest {
    @Test
    void logsDailyReportSavedAndSubmittedAfterSuccessfulServiceCalls(CapturedOutput output) {
        DailyReportCommandService commandService = mock(DailyReportCommandService.class);
        DailyReportRequest request = mock(DailyReportRequest.class);
        AuthenticatedUser principal = mock(AuthenticatedUser.class);
        when(commandService.create(request, principal))
                .thenReturn(new DailyReportSummaryResponse("R-LOG-001", ApprovalStatus.DRAFT));
        when(commandService.update("R-LOG-001", request, principal))
                .thenReturn(new DailyReportSummaryResponse("R-LOG-001", ApprovalStatus.DRAFT));

        DailyReportSubmissionService submissionService = mock(DailyReportSubmissionService.class);
        when(submissionService.submit("R-LOG-001", principal))
                .thenReturn(new SubmitResponse("R-LOG-001", ApprovalStatus.PENDING, OffsetDateTime.now()));

        DailyReportCommandController commandController = new DailyReportCommandController(commandService);
        ResponseEntity<DailyReportSummaryResponse> created = commandController.create(request, principal);
        commandController.update("R-LOG-001", request, principal);
        new DailyReportSubmissionController(submissionService).submit("R-LOG-001", principal);

        assertThat(created.getBody()).isNotNull();
        assertThat(output).contains("event=daily_report.saved");
        assertThat(output).contains("useCase=CREATE");
        assertThat(output).contains("useCase=UPDATE");
        assertThat(output).contains("event=daily_report.submitted");
        assertThat(output).contains("reportId=R-LOG-001");
    }

    @Test
    void logsAuthenticationSuccessWithoutPassword(CapturedOutput output) {
        AuthenticationManager authenticationManager = mock(AuthenticationManager.class);
        Authentication authentication = mock(Authentication.class);
        AppUser user = new AppUser("U-LOG", "E-LOG", "employee-log", "hashed-password", "ログイン利用者",
                Role.EMPLOYEE, "G-LOG", "ロググループ", "BT-LOG", "標準休憩", "WT-LOG", "通常勤務");
        when(authenticationManager.authenticate(any())).thenReturn(authentication);
        when(authentication.getPrincipal()).thenReturn(new AuthenticatedUser(user));

        AuthController controller = new AuthController(authenticationManager);
        controller.login(new LoginRequest("employee-log", "secret-password"), new MockHttpServletRequest());
        controller.logout(new MockHttpServletRequest(), new MockHttpServletResponse());

        assertThat(output).contains("event=auth.login_succeeded");
        assertThat(output).contains("event=auth.logout_succeeded");
        assertThat(output).doesNotContain("secret-password");
        assertThat(output).doesNotContain("hashed-password");
    }
}

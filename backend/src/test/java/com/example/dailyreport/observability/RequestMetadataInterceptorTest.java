package com.example.dailyreport.observability;

import static org.assertj.core.api.Assertions.assertThat;

import com.example.dailyreport.auth.AuthenticatedUser;
import com.example.dailyreport.auth.AuthController;
import com.example.dailyreport.master.MasterController;
import com.example.dailyreport.report.DailyReportApprovalService;
import com.example.dailyreport.report.DailyReportPendingApprovalService;
import com.example.dailyreport.report.controller.DailyReportApprovalController;
import com.example.dailyreport.report.controller.DailyReportCommandController;
import com.example.dailyreport.report.controller.DailyReportPendingApprovalController;
import com.example.dailyreport.report.dto.DailyReportRequest;
import com.example.dailyreport.report.dto.RejectRequest;
import java.lang.reflect.Method;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.web.method.HandlerMethod;

class RequestMetadataInterceptorTest {
    @Test
    void resolvesDailyReportCreateMetadata() throws Exception {
        Method method = DailyReportCommandController.class.getMethod(
                "create", DailyReportRequest.class, AuthenticatedUser.class);
        HandlerMethod handler = new HandlerMethod(new DailyReportCommandController(null), method);
        MockHttpServletRequest request = new MockHttpServletRequest("POST", "/api/daily-reports");

        new RequestMetadataInterceptor().preHandle(request, new MockHttpServletResponse(), handler);

        assertThat(request.getAttribute(RequestContext.FEATURE_ATTRIBUTE)).isEqualTo("DAILY_REPORT");
        assertThat(request.getAttribute(RequestContext.USE_CASE_ATTRIBUTE)).isEqualTo("CREATE");
    }

    @Test
    void resolvesApprovalAndRejectionMetadataForMvcAndSecurityPaths() throws Exception {
        RequestMetadataInterceptor interceptor = new RequestMetadataInterceptor();
        DailyReportApprovalController controller = new DailyReportApprovalController((DailyReportApprovalService) null);
        MockHttpServletResponse response = new MockHttpServletResponse();

        MockHttpServletRequest approveRequest = new MockHttpServletRequest("POST", "/api/daily-reports/R-APR-001/approve");
        interceptor.preHandle(approveRequest, response, new HandlerMethod(controller,
                DailyReportApprovalController.class.getMethod("approve", String.class, AuthenticatedUser.class)));

        MockHttpServletRequest rejectRequest = new MockHttpServletRequest("POST", "/api/daily-reports/R-APR-001/reject");
        interceptor.preHandle(rejectRequest, response, new HandlerMethod(controller,
                DailyReportApprovalController.class.getMethod("reject", String.class, RejectRequest.class,
                        AuthenticatedUser.class)));

        assertThat(approveRequest.getAttribute(RequestContext.FEATURE_ATTRIBUTE)).isEqualTo("DAILY_REPORT");
        assertThat(approveRequest.getAttribute(RequestContext.USE_CASE_ATTRIBUTE)).isEqualTo("APPROVE");
        assertThat(rejectRequest.getAttribute(RequestContext.FEATURE_ATTRIBUTE)).isEqualTo("DAILY_REPORT");
        assertThat(rejectRequest.getAttribute(RequestContext.USE_CASE_ATTRIBUTE)).isEqualTo("REJECT");
        assertThat(RequestContext.featureForPath("/api/daily-reports/R-APR-001/approve"))
                .isEqualTo("DAILY_REPORT");
        assertThat(RequestContext.useCaseForPath("POST", "/api/daily-reports/R-APR-001/approve"))
                .isEqualTo("APPROVE");
        assertThat(RequestContext.featureForPath("/api/daily-reports/R-APR-001/reject"))
                .isEqualTo("DAILY_REPORT");
        assertThat(RequestContext.useCaseForPath("POST", "/api/daily-reports/R-APR-001/reject"))
                .isEqualTo("REJECT");
    }

    @Test
    void resolvesPendingApprovalsMetadataForMvcAndSecurityPaths() throws Exception {
        RequestMetadataInterceptor interceptor = new RequestMetadataInterceptor();
        DailyReportPendingApprovalController controller = new DailyReportPendingApprovalController(
                (DailyReportPendingApprovalService) null);
        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/api/daily-reports/pending-approvals");

        interceptor.preHandle(request, new MockHttpServletResponse(), new HandlerMethod(controller,
                DailyReportPendingApprovalController.class.getMethod("pendingApprovals", java.time.LocalDate.class,
                        java.time.LocalDate.class, String.class, String.class, AuthenticatedUser.class)));

        assertThat(request.getAttribute(RequestContext.FEATURE_ATTRIBUTE)).isEqualTo("DAILY_REPORT");
        assertThat(request.getAttribute(RequestContext.USE_CASE_ATTRIBUTE)).isEqualTo("PENDING_APPROVALS");
        assertThat(RequestContext.featureForPath("/api/daily-reports/pending-approvals")).isEqualTo("DAILY_REPORT");
        assertThat(RequestContext.useCaseForPath("GET", "/api/daily-reports/pending-approvals"))
                .isEqualTo("PENDING_APPROVALS");
    }

    @Test
    void resolvesAuthAndMasterFeatures() throws Exception {
        RequestMetadataInterceptor interceptor = new RequestMetadataInterceptor();
        MockHttpServletResponse response = new MockHttpServletResponse();

        MockHttpServletRequest authRequest = new MockHttpServletRequest("POST", "/api/auth/login");
        interceptor.preHandle(authRequest, response,
                new HandlerMethod(new AuthController(null), AuthController.class.getMethod(
                        "login", com.example.dailyreport.auth.LoginRequest.class,
                        jakarta.servlet.http.HttpServletRequest.class)));

        MockHttpServletRequest masterRequest = new MockHttpServletRequest("GET", "/api/master/projects");
        interceptor.preHandle(masterRequest, response,
                new HandlerMethod(new MasterController(null), MasterController.class.getMethod("projects")));

        assertThat(authRequest.getAttribute(RequestContext.FEATURE_ATTRIBUTE)).isEqualTo("AUTH");
        assertThat(authRequest.getAttribute(RequestContext.USE_CASE_ATTRIBUTE)).isEqualTo("LOGIN");
        assertThat(masterRequest.getAttribute(RequestContext.FEATURE_ATTRIBUTE)).isEqualTo("MASTER");
        assertThat(masterRequest.getAttribute(RequestContext.USE_CASE_ATTRIBUTE)).isEqualTo("PROJECTS");
    }

    @Test
    void labelsUnknownHandlerWithoutThrowing() throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/unknown");

        new RequestMetadataInterceptor().preHandle(request, new MockHttpServletResponse(),
                new HandlerMethod(new Object(), Object.class.getMethod("toString")));

        assertThat(request.getAttribute(RequestContext.FEATURE_ATTRIBUTE)).isEqualTo("UNKNOWN");
        assertThat(request.getAttribute(RequestContext.USE_CASE_ATTRIBUTE)).isEqualTo("UNKNOWN");
    }
}

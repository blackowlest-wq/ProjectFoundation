package com.example.dailyreport.observability;

import static org.assertj.core.api.Assertions.assertThat;

import com.example.dailyreport.auth.AuthenticatedUser;
import com.example.dailyreport.auth.AuthController;
import com.example.dailyreport.master.MasterController;
import com.example.dailyreport.report.controller.DailyReportCommandController;
import com.example.dailyreport.report.dto.DailyReportRequest;
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

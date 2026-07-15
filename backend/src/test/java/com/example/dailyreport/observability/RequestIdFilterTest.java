package com.example.dailyreport.observability;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import ch.qos.logback.classic.Level;
import ch.qos.logback.classic.Logger;
import java.io.IOException;
import java.util.concurrent.atomic.AtomicReference;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;
import org.springframework.boot.test.system.CapturedOutput;
import org.springframework.boot.test.system.OutputCaptureExtension;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;

@ExtendWith(OutputCaptureExtension.class)
class RequestIdFilterTest {
    private final Logger filterLogger = (Logger) LoggerFactory.getLogger(RequestIdFilter.class);
    private Level originalLevel;

    @AfterEach
    void restoreLoggerLevel() {
        if (originalLevel != null) {
            filterLogger.setLevel(originalLevel);
        }
        MDC.clear();
    }

    @Test
    void addsCorrelationIdHeaderAndCleansMdcAfterSuccessfulRequest() throws Exception {
        RequestIdFilter filter = new RequestIdFilter();
        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/api/master/projects");
        MockHttpServletResponse response = new MockHttpServletResponse();
        AtomicReference<String> requestIdDuringChain = new AtomicReference<>();

        filter.doFilter(request, response, (servletRequest, servletResponse) -> {
            requestIdDuringChain.set(MDC.get(RequestContext.MDC_KEY));
            assertThat(servletRequest.getAttribute(RequestContext.REQUEST_ID_ATTRIBUTE)).isEqualTo(requestIdDuringChain.get());
        });

        assertThat(response.getHeader(RequestContext.REQUEST_ID_HEADER)).matches(
                "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}");
        assertThat(requestIdDuringChain.get()).isEqualTo(response.getHeader(RequestContext.REQUEST_ID_HEADER));
        assertThat(MDC.get(RequestContext.MDC_KEY)).isNull();
    }

    @Test
    void logsRequestCompletionWithStableTraceFields(CapturedOutput output) throws Exception {
        originalLevel = filterLogger.getLevel();
        filterLogger.setLevel(Level.DEBUG);

        RequestIdFilter filter = new RequestIdFilter();
        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/api/master/projects");
        MockHttpServletResponse response = new MockHttpServletResponse();
        response.setStatus(200);

        filter.doFilter(request, response, (servletRequest, servletResponse) -> {
            ((MockHttpServletResponse) servletResponse).setStatus(200);
        });

        assertThat(output).contains("event=request.completed");
        assertThat(output).contains("method=GET");
        assertThat(output).contains("path=/api/master/projects");
        assertThat(output).contains("feature=MASTER");
        assertThat(output).contains("useCase=PROJECTS");
        assertThat(output).contains("status=200");
        assertThat(output).contains("durationMs=");
    }

    @Test
    void logsAndRethrowsUnexpectedFilterFailure(CapturedOutput output) {
        originalLevel = filterLogger.getLevel();
        filterLogger.setLevel(Level.DEBUG);

        RequestIdFilter filter = new RequestIdFilter();
        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/api/failure");
        MockHttpServletResponse response = new MockHttpServletResponse();
        IOException failure = new IOException("test failure");

        assertThatThrownBy(() -> filter.doFilter(request, response, (servletRequest, servletResponse) -> {
            throw failure;
        })).isSameAs(failure);
        assertThat(MDC.get(RequestContext.MDC_KEY)).isNull();
        assertThat(output).contains("event=request.failed");
        assertThat(output.getOut()).containsPattern("event=request.completed[^\\r\\n]*status=500");
    }
}

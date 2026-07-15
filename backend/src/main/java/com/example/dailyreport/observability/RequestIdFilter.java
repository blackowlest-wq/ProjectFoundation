/**
 * 全HTTPリクエストへ相関IDを付与し、MDCへ設定してリクエストの開始・完了を記録する。
 */
package com.example.dailyreport.observability;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.UUID;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

@Component
@Order(Ordered.HIGHEST_PRECEDENCE)
public class RequestIdFilter extends OncePerRequestFilter {
    private static final Logger LOGGER = LoggerFactory.getLogger(RequestIdFilter.class);

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain filterChain)
            throws ServletException, IOException {
        String requestId = UUID.randomUUID().toString();
        String previousRequestId = MDC.get(RequestContext.MDC_KEY);
        long startedAt = System.nanoTime();
        request.setAttribute(RequestContext.REQUEST_ID_ATTRIBUTE, requestId);
        request.setAttribute(RequestContext.FEATURE_ATTRIBUTE,
                RequestContext.featureForPath(request.getRequestURI()));
        request.setAttribute(RequestContext.USE_CASE_ATTRIBUTE,
                RequestContext.useCaseForPath(request.getMethod(), request.getRequestURI()));
        response.setHeader(RequestContext.REQUEST_ID_HEADER, requestId);
        MDC.put(RequestContext.MDC_KEY, requestId);
        int failureStatusForCompletion = 0;

        LOGGER.debug("event=request.started requestId={} method={} path={}", requestId,
                request.getMethod(), request.getRequestURI());
        try {
            filterChain.doFilter(request, response);
        } catch (IOException | ServletException | RuntimeException | Error exception) {
            int failureStatus = response.getStatus() >= HttpServletResponse.SC_BAD_REQUEST
                    ? response.getStatus()
                    : HttpServletResponse.SC_INTERNAL_SERVER_ERROR;
            failureStatusForCompletion = failureStatus;
            LOGGER.error("event=request.failed requestId={} method={} path={} feature={} useCase={} status={} exceptionType={} exceptionTrace={}",
                    requestId, request.getMethod(), request.getRequestURI(), RequestContext.feature(request),
                    RequestContext.useCase(request), failureStatus, ExceptionLog.type(exception), ExceptionLog.stack(exception));
            throw exception;
        } finally {
            long durationMs = Math.max(0L, (System.nanoTime() - startedAt) / 1_000_000L);
            LOGGER.debug("event=request.completed requestId={} method={} path={} feature={} useCase={} status={} durationMs={}",
                    requestId, request.getMethod(), request.getRequestURI(), RequestContext.feature(request),
                    RequestContext.useCase(request), failureStatusForCompletion == 0
                            ? response.getStatus() : failureStatusForCompletion,
                    durationMs);
            if (previousRequestId == null) {
                MDC.remove(RequestContext.MDC_KEY);
            } else {
                MDC.put(RequestContext.MDC_KEY, previousRequestId);
            }
        }
    }
}

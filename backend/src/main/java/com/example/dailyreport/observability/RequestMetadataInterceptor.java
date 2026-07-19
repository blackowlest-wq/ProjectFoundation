/**
 * MVCのHandlerMethodからログ用の機能名とユースケース名を解決する。
 */
package com.example.dailyreport.observability;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.util.Map;
import org.springframework.web.method.HandlerMethod;
import org.springframework.web.servlet.HandlerInterceptor;

public class RequestMetadataInterceptor implements HandlerInterceptor {
    private static final Map<String, String> FEATURE_BY_CONTROLLER = Map.of(
            "AuthController", "AUTH",
            "DailyReportCommandController", "DAILY_REPORT",
            "DailyReportSubmissionController", "DAILY_REPORT",
            "DailyReportSearchController", "DAILY_REPORT",
            "DailyReportApprovalController", "DAILY_REPORT",
            "MasterController", "MASTER");

    private static final Map<String, String> USE_CASE_BY_METHOD = Map.ofEntries(
            Map.entry("login", "LOGIN"),
            Map.entry("logout", "LOGOUT"),
            Map.entry("me", "ME"),
            Map.entry("create", "CREATE"),
            Map.entry("update", "UPDATE"),
            Map.entry("submit", "SUBMIT"),
            Map.entry("resubmit", "RESUBMIT"),
            Map.entry("search", "SEARCH"),
            Map.entry("get", "DETAIL"),
            Map.entry("approve", "APPROVE"),
            Map.entry("reject", "REJECT"),
            Map.entry("projects", "PROJECTS"),
            Map.entry("workCategories", "WORK_CATEGORIES"),
            Map.entry("holidayTypes", "HOLIDAY_TYPES"));

    @Override
    public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler) {
        if (handler instanceof HandlerMethod handlerMethod) {
            String controllerName = handlerMethod.getBeanType().getSimpleName();
            String methodName = handlerMethod.getMethod().getName();
            request.setAttribute(RequestContext.FEATURE_ATTRIBUTE,
                    FEATURE_BY_CONTROLLER.getOrDefault(controllerName, RequestContext.UNKNOWN));
            request.setAttribute(RequestContext.USE_CASE_ATTRIBUTE,
                    USE_CASE_BY_METHOD.getOrDefault(methodName, RequestContext.UNKNOWN));
        } else {
            request.setAttribute(RequestContext.FEATURE_ATTRIBUTE, RequestContext.UNKNOWN);
            request.setAttribute(RequestContext.USE_CASE_ATTRIBUTE, RequestContext.UNKNOWN);
        }
        return true;
    }
}

/**
 * リクエスト単位の観測用属性名と安全な参照処理をまとめる。
 */
package com.example.dailyreport.observability;

import jakarta.servlet.http.HttpServletRequest;
import java.util.List;
import java.util.regex.Pattern;

public final class RequestContext {
    public static final String REQUEST_ID_HEADER = "X-Request-Id";
    public static final String MDC_KEY = "requestId";
    public static final String REQUEST_ID_ATTRIBUTE = RequestContext.class.getName() + ".requestId";
    public static final String FEATURE_ATTRIBUTE = RequestContext.class.getName() + ".feature";
    public static final String USE_CASE_ATTRIBUTE = RequestContext.class.getName() + ".useCase";
    public static final String UNKNOWN = "UNKNOWN";
    private static final List<RouteMapping> USE_CASE_ROUTES = List.of(
            route("POST", "/api/auth/login", "LOGIN"),
            route("POST", "/api/auth/logout", "LOGOUT"),
            route("GET", "/api/auth/me", "ME"),
            route("POST", "/api/daily-reports", "CREATE"),
            route("GET", "/api/daily-reports", "SEARCH"),
            route("GET", "/api/daily-reports/pending-approvals", "PENDING_APPROVALS"),
            route("PUT", "/api/daily-reports/[^/]+", "UPDATE"),
            route("GET", "/api/daily-reports/[^/]+", "DETAIL"),
            route("POST", "/api/daily-reports/[^/]+/submit", "SUBMIT"),
            route("POST", "/api/daily-reports/[^/]+/resubmit", "RESUBMIT"),
            route("POST", "/api/daily-reports/[^/]+/approve", "APPROVE"),
            route("POST", "/api/daily-reports/[^/]+/reject", "REJECT"),
            route("GET", "/api/master/projects", "PROJECTS"),
            route("GET", "/api/master/work-categories", "WORK_CATEGORIES"),
            route("GET", "/api/master/holiday-types", "HOLIDAY_TYPES"),
            route("GET", "/api/monthly-summaries", "MONTHLY_SUMMARY"));

    private RequestContext() {
    }

    public static String requestId(HttpServletRequest request) {
        return attribute(request, REQUEST_ID_ATTRIBUTE, UNKNOWN);
    }

    public static String feature(HttpServletRequest request) {
        return attribute(request, FEATURE_ATTRIBUTE, UNKNOWN);
    }

    public static String useCase(HttpServletRequest request) {
        return attribute(request, USE_CASE_ATTRIBUTE, UNKNOWN);
    }

    public static String featureForPath(String path) {
        if (path.startsWith("/api/auth")) {
            return "AUTH";
        }
        if (path.startsWith("/api/daily-reports")) {
            return "DAILY_REPORT";
        }
        if (path.startsWith("/api/master")) {
            return "MASTER";
        }
        if (path.startsWith("/api/monthly-summaries")) {
            return "MONTHLY_SUMMARY";
        }
        return UNKNOWN;
    }

    public static String useCaseForPath(String method, String path) {
        return USE_CASE_ROUTES.stream()
                .filter(route -> route.matches(method, path))
                .map(RouteMapping::useCase)
                .findFirst()
                .orElse(UNKNOWN);
    }

    private static RouteMapping route(String method, String pathPattern, String useCase) {
        return new RouteMapping(method, Pattern.compile(pathPattern), useCase);
    }

    private record RouteMapping(String method, Pattern pathPattern, String useCase) {
        private boolean matches(String requestMethod, String requestPath) {
            return method.equals(requestMethod) && pathPattern.matcher(requestPath).matches();
        }
    }

    private static String attribute(HttpServletRequest request, String name, String fallback) {
        Object value = request.getAttribute(name);
        if (value instanceof String stringValue && !stringValue.isBlank()) {
            return stringValue;
        }
        return fallback;
    }
}

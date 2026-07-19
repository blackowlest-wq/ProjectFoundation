/**
 * リクエスト単位の観測用属性名と安全な参照処理をまとめる。
 */
package com.example.dailyreport.observability;

import jakarta.servlet.http.HttpServletRequest;

public final class RequestContext {
    public static final String REQUEST_ID_HEADER = "X-Request-Id";
    public static final String MDC_KEY = "requestId";
    public static final String REQUEST_ID_ATTRIBUTE = RequestContext.class.getName() + ".requestId";
    public static final String FEATURE_ATTRIBUTE = RequestContext.class.getName() + ".feature";
    public static final String USE_CASE_ATTRIBUTE = RequestContext.class.getName() + ".useCase";
    public static final String UNKNOWN = "UNKNOWN";

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
        return UNKNOWN;
    }

    public static String useCaseForPath(String method, String path) {
        if ("POST".equals(method) && path.equals("/api/auth/login")) {
            return "LOGIN";
        }
        if ("POST".equals(method) && path.equals("/api/auth/logout")) {
            return "LOGOUT";
        }
        if ("GET".equals(method) && path.equals("/api/auth/me")) {
            return "ME";
        }
        if ("POST".equals(method) && path.equals("/api/daily-reports")) {
            return "CREATE";
        }
        if ("GET".equals(method) && path.equals("/api/daily-reports")) {
            return "SEARCH";
        }
        if ("GET".equals(method) && path.equals("/api/daily-reports/pending-approvals")) {
            return "PENDING_APPROVALS";
        }
        if ("PUT".equals(method) && path.matches("/api/daily-reports/[^/]+")) {
            return "UPDATE";
        }
        if ("GET".equals(method) && path.matches("/api/daily-reports/[^/]+")) {
            return "DETAIL";
        }
        if ("POST".equals(method) && path.matches("/api/daily-reports/[^/]+/submit")) {
            return "SUBMIT";
        }
        if ("POST".equals(method) && path.matches("/api/daily-reports/[^/]+/resubmit")) {
            return "RESUBMIT";
        }
        if ("POST".equals(method) && path.matches("/api/daily-reports/[^/]+/approve")) {
            return "APPROVE";
        }
        if ("POST".equals(method) && path.matches("/api/daily-reports/[^/]+/reject")) {
            return "REJECT";
        }
        if ("GET".equals(method) && path.equals("/api/master/projects")) {
            return "PROJECTS";
        }
        if ("GET".equals(method) && path.equals("/api/master/work-categories")) {
            return "WORK_CATEGORIES";
        }
        if ("GET".equals(method) && path.equals("/api/master/holiday-types")) {
            return "HOLIDAY_TYPES";
        }
        return UNKNOWN;
    }

    private static String attribute(HttpServletRequest request, String name, String fallback) {
        Object value = request.getAttribute(name);
        if (value instanceof String stringValue && !stringValue.isBlank()) {
            return stringValue;
        }
        return fallback;
    }
}

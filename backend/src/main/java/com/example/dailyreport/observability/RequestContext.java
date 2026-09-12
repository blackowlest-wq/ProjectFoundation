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
        return EndpointMetadataRegistry.defaultRegistry().featureForPath(path);
    }

    public static String useCaseForPath(String method, String path) {
        return EndpointMetadataRegistry.defaultRegistry().useCaseForPath(method, path);
    }

    private static String attribute(HttpServletRequest request, String name, String fallback) {
        Object value = request.getAttribute(name);
        if (value instanceof String stringValue && !stringValue.isBlank()) {
            return stringValue;
        }
        return fallback;
    }
}

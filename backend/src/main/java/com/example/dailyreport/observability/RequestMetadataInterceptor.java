/**
 * MVCのHandlerMethodからログ用の機能名とユースケース名を解決する。
 */
package com.example.dailyreport.observability;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.web.method.HandlerMethod;
import org.springframework.web.servlet.HandlerInterceptor;

public class RequestMetadataInterceptor implements HandlerInterceptor {
    private static final MetadataLookup DEFAULT_LOOKUP = EndpointMetadataRegistry.defaultRegistry()::lookup;
    private final MetadataLookup metadataLookup;

    public RequestMetadataInterceptor() {
        this.metadataLookup = DEFAULT_LOOKUP;
    }

    public RequestMetadataInterceptor(EndpointMetadataRegistry registry) {
        if (registry == null) {
            this.metadataLookup = DEFAULT_LOOKUP;
        } else {
            this.metadataLookup = (httpMethod, requestPath, handlerMethod) ->
                    registry.lookup(httpMethod, requestPath, handlerMethod);
        }
    }

    @Override
    public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler) {
        if (handler instanceof HandlerMethod handlerMethod) {
            EndpointMetadataRegistry.EndpointMetadata metadata = metadataLookup
                    .lookup(request.getMethod(), request.getRequestURI(), handlerMethod)
                    .orElse(null);
            request.setAttribute(RequestContext.FEATURE_ATTRIBUTE,
                    metadata == null ? RequestContext.UNKNOWN : metadata.feature());
            request.setAttribute(RequestContext.USE_CASE_ATTRIBUTE,
                    metadata == null ? RequestContext.UNKNOWN : metadata.useCase());
        } else {
            request.setAttribute(RequestContext.FEATURE_ATTRIBUTE,
                    RequestContext.UNKNOWN);
            request.setAttribute(RequestContext.USE_CASE_ATTRIBUTE,
                    RequestContext.UNKNOWN);
        }
        return true;
    }

    @FunctionalInterface
    private interface MetadataLookup {
        java.util.Optional<EndpointMetadataRegistry.EndpointMetadata> lookup(
                String httpMethod, String requestPath, HandlerMethod handlerMethod);
    }
}

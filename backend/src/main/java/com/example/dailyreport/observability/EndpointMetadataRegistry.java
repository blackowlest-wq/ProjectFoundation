/**
 * Spring MVCの公開エンドポイントと観測用メタデータを一元管理する。
 *
 * <p>Controllerのアノテーションを静的に再解釈せず、Springが登録した
 * {@code RequestMappingHandlerMapping}を検証の入力にする。実際のmappingと
 * registryの差分を検出し、リクエスト時の機能名・ユースケース名の解決も
 * 同じregistryへ委譲する。</p>
 */
package com.example.dailyreport.observability;

import com.example.dailyreport.auth.AuthController;
import com.example.dailyreport.master.MasterController;
import com.example.dailyreport.master.MessageCatalogController;
import com.example.dailyreport.monthlysummary.MonthlySummaryController;
import com.example.dailyreport.report.controller.DailyReportApprovalController;
import com.example.dailyreport.report.controller.DailyReportCommandController;
import com.example.dailyreport.report.controller.DailyReportPendingApprovalController;
import com.example.dailyreport.report.controller.DailyReportSearchController;
import com.example.dailyreport.report.controller.DailyReportSubmissionController;
import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collection;
import java.util.Collections;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Objects;
import java.util.Optional;
import java.util.Set;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import org.springframework.beans.factory.SmartInitializingSingleton;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.Lazy;
import org.springframework.stereotype.Component;
import org.springframework.web.method.HandlerMethod;
import org.springframework.web.servlet.mvc.method.RequestMappingInfo;
import org.springframework.web.servlet.mvc.method.annotation.RequestMappingHandlerMapping;
import org.springframework.web.util.pattern.PathPattern;
import org.springframework.web.util.pattern.PathPatternParser;

@Component
public final class EndpointMetadataRegistry implements SmartInitializingSingleton {
    public static final String APPLICATION_PACKAGE_PREFIX = "com.example.dailyreport";
    private static final Pattern PATH_VARIABLE_PATTERN = Pattern.compile("\\{([^}:]+)(?::[^}]*)?}");
    private static final PathPatternParser PATH_PATTERN_PARSER = PathPatternParser.defaultInstance;
    private static final List<EndpointMetadata> STANDARD_METADATA = standardMetadata();
    private final RequestMappingHandlerMapping handlerMapping;
    private final CopyOnWriteArrayList<EndpointMetadata> entries;
    private volatile ValidationReport lastValidation;

    /**
     * Spring管理外のInterceptorやFilterから参照する標準registryを生成する。
     */
    public EndpointMetadataRegistry() {
        this(null, STANDARD_METADATA);
    }

    /**
     * 空のregistryを生成する。テストや追加の境界検証で利用する。
     */
    public EndpointMetadataRegistry(Collection<EndpointMetadata> initialEntries) {
        this(null, initialEntries);
    }

    /**
     * 実Springのmappingを検証対象としてregistryを生成する。
     */
    @Autowired
    public EndpointMetadataRegistry(@Lazy RequestMappingHandlerMapping handlerMapping) {
        this(handlerMapping, STANDARD_METADATA);
    }

    private EndpointMetadataRegistry(RequestMappingHandlerMapping handlerMapping,
                                     Collection<EndpointMetadata> initialEntries) {
        this.handlerMapping = handlerMapping;
        this.entries = new CopyOnWriteArrayList<>();
        if (initialEntries != null) {
            this.entries.addAll(initialEntries);
        }
    }

    /**
     * Springコンテキストを使わないFilter/Interceptor用の標準registryを返す。
     */
    public static EndpointMetadataRegistry standard() {
        return new EndpointMetadataRegistry(null, STANDARD_METADATA);
    }

    /**
     * 標準メタデータを共有する読み取り専用registryを返す。
     */
    public static EndpointMetadataRegistry defaultRegistry() {
        return standard();
    }

    /**
     * registryへメタデータを一件追加する。
     */
    public void register(EndpointMetadata metadata) {
        entries.add(Objects.requireNonNull(metadata, "metadata"));
    }

    /**
     * HandlerMethodを使ってregistryへメタデータを一件追加する。
     */
    public void register(String httpMethod, String route, HandlerMethod handlerMethod,
                         String feature, String useCase) {
        register(new EndpointMetadata(httpMethod, route, handlerMethod, feature, useCase));
    }

    /**
     * Controller型とJavaメソッドを使ってregistryへメタデータを一件追加する。
     */
    public void register(String httpMethod, String route, Class<?> beanType, Method method,
                         String feature, String useCase) {
        register(new EndpointMetadata(httpMethod, route, beanType, method, feature, useCase));
    }

    /**
     * 登録済みメタデータのスナップショットを返す。
     */
    public List<EndpointMetadata> entries() {
        return List.copyOf(entries);
    }

    /**
     * registryを空にする。標準registry本体には影響しない。
     */
    public void clear() {
        entries.clear();
    }

    /**
     * HTTPメソッド・リクエストパス・HandlerMethodからメタデータを解決する。
     */
    public Optional<EndpointMetadata> lookup(String httpMethod, String requestPath,
                                              HandlerMethod handlerMethod) {
        String normalizedMethod = normalizeHttpMethod(httpMethod);
        String normalizedPath = normalizeRequestPath(requestPath);
        boolean methodProvided = httpMethod != null && !httpMethod.isBlank();
        return entries.stream()
                .filter(entry -> !methodProvided || normalizedMethod.equals(entry.httpMethod()))
                .filter(entry -> handlerMethod == null || entry.matches(handlerMethod))
                .filter(entry -> routeMatches(entry.normalizedRoute(), normalizedPath))
                .sorted(Comparator.comparing(EndpointMetadata::normalizedRoute,
                        EndpointMetadataRegistry::compareRouteSpecificity))
                .findFirst();
    }

    /**
     * Security前のFilterなどHandlerMethodを取得できない経路からメタデータを解決する。
     */
    public Optional<EndpointMetadata> lookup(String httpMethod, String requestPath) {
        return lookup(httpMethod, requestPath, null);
    }

    /**
     * Security前のFilterから機能名だけを安全に解決する。
     */
    public String featureForPath(String requestPath) {
        return lookup(null, requestPath).map(EndpointMetadata::feature)
                .orElse(RequestContext.UNKNOWN);
    }

    /**
     * Security前のFilterからユースケース名を安全に解決する。
     */
    public String useCaseForPath(String httpMethod, String requestPath) {
        return lookup(httpMethod, requestPath).map(EndpointMetadata::useCase)
                .orElse(RequestContext.UNKNOWN);
    }

    /**
     * Springのsingleton初期化完了後にlive mappingを検証する。
     */
    @Override
    public void afterSingletonsInstantiated() {
        if (handlerMapping == null) {
            return;
        }
        ValidationReport validation = validateLiveMappings();
        lastValidation = validation;
        if (!validation.isValid()) {
            throw new EndpointMetadataValidationException();
        }
    }

    /**
     * 直近のlive mapping検証結果を返す。
     */
    public Optional<ValidationReport> lastValidation() {
        return Optional.ofNullable(lastValidation);
    }

    /**
     * 注入された実SpringのRequestMappingHandlerMappingを検証する。
     */
    public ValidationReport validateLiveMappings() {
        if (handlerMapping == null) {
            return validate(Collections.emptyMap());
        }
        return validate(handlerMapping.getHandlerMethods());
    }

    /**
     * 指定されたSpring mappingとregistryを比較する。
     */
    public ValidationReport validate(Map<RequestMappingInfo, HandlerMethod> liveMappings) {
        ValidationAccumulator accumulator = new ValidationAccumulator();
        Map<RouteKey, List<EndpointMetadata>> registeredByRoute = groupRegisteredEntries(accumulator);
        Map<RouteKey, List<LiveEndpoint>> liveByRoute = collectLiveEndpoints(liveMappings, accumulator);

        registeredByRoute.forEach((key, registered) -> {
            List<LiveEndpoint> live = liveByRoute.getOrDefault(key, List.of());
            if (live.isEmpty()) {
                accumulator.violate(ViolationType.ORPHAN,
                        "orphan EndpointMetadataRegistry entry");
                return;
            }
            for (EndpointMetadata metadata : registered) {
                boolean handlerMatches = live.stream().anyMatch(endpoint -> metadata.matches(endpoint.handlerMethod()));
                if (!handlerMatches) {
                    accumulator.violate(ViolationType.MISMATCH,
                            "HandlerMethod mismatch for " + key.display());
                }
            }
        });

        liveByRoute.forEach((key, live) -> {
            if (!registeredByRoute.containsKey(key)) {
                accumulator.violate(ViolationType.MISMATCH,
                        "mapping is not registered for " + key.display());
            }
        });
        return accumulator.report(entries.size());
    }

    /**
     * live mappingの対象判定とHTTP method展開を公開する。
     */
    public LiveMappingSnapshot snapshot(Map<RequestMappingInfo, HandlerMethod> liveMappings) {
        ValidationAccumulator accumulator = new ValidationAccumulator();
        Map<RouteKey, List<LiveEndpoint>> liveByRoute = collectLiveEndpoints(liveMappings, accumulator);
        List<LiveEndpoint> endpoints = liveByRoute.values().stream()
                .flatMap(Collection::stream)
                .toList();
        return new LiveMappingSnapshot(endpoints, accumulator.applicationMappingCount,
                accumulator.excludedMappingCount, accumulator.violations());
    }

    /**
     * HTTP methodを大文字へ統一する。
     */
    public static String normalizeHttpMethod(String httpMethod) {
        return httpMethod == null ? "" : httpMethod.trim().toUpperCase(Locale.ROOT);
    }

    /**
     * Spring mappingのroute表記をregistry比較用に統一する。
     */
    public static String normalizeRoute(String route) {
        if (route == null || route.isBlank()) {
            return "/";
        }
        String normalized = route.trim().replace('\\', '/');
        if (!normalized.startsWith("/")) {
            normalized = "/" + normalized;
        }
        normalized = normalized.replaceAll("/{2,}", "/");
        Matcher matcher = PATH_VARIABLE_PATTERN.matcher(normalized);
        StringBuffer result = new StringBuffer();
        while (matcher.find()) {
            matcher.appendReplacement(result, Matcher.quoteReplacement("{" + matcher.group(1) + "}"));
        }
        matcher.appendTail(result);
        return result.toString();
    }

    private static String normalizeRequestPath(String path) {
        return normalizeRoute(path == null ? "/" : path.split("\\?", 2)[0]);
    }

    private static boolean routeMatches(String route, String requestPath) {
        try {
            PathPattern pattern = PATH_PATTERN_PARSER.parse(normalizeRoute(route));
            return pattern.matches(org.springframework.http.server.PathContainer.parsePath(requestPath));
        } catch (IllegalArgumentException exception) {
            return false;
        }
    }

    private static int compareRouteSpecificity(String left, String right) {
        try {
            return PathPattern.SPECIFICITY_COMPARATOR.compare(
                    PATH_PATTERN_PARSER.parse(normalizeRoute(left)),
                    PATH_PATTERN_PARSER.parse(normalizeRoute(right)));
        } catch (IllegalArgumentException exception) {
            return left.compareTo(right);
        }
    }

    private Map<RouteKey, List<EndpointMetadata>> groupRegisteredEntries(ValidationAccumulator accumulator) {
        Map<RouteKey, List<EndpointMetadata>> grouped = new LinkedHashMap<>();
        for (EndpointMetadata metadata : entries) {
            if (metadata.handlerMethod() == null) {
                accumulator.violate(ViolationType.MISSING_HANDLER_METHOD, "HandlerMethod is required");
            }
            if (RequestContext.UNKNOWN.equals(metadata.feature())) {
                accumulator.violate(ViolationType.UNKNOWN_METADATA,
                        "metadata feature must not be UNKNOWN");
            }
            if (RequestContext.UNKNOWN.equals(metadata.useCase())) {
                accumulator.violate(ViolationType.UNKNOWN_METADATA,
                        "metadata useCase must not be UNKNOWN");
            }
            RouteKey key = new RouteKey(metadata.httpMethod(), metadata.normalizedRoute());
            List<EndpointMetadata> sameKey = grouped.computeIfAbsent(key, ignored -> new ArrayList<>());
            if (!sameKey.isEmpty()) {
                accumulator.violate(ViolationType.DUPLICATE,
                        "duplicate registry key " + key.display());
            }
            sameKey.add(metadata);
        }
        return grouped;
    }

    private Map<RouteKey, List<LiveEndpoint>> collectLiveEndpoints(
            Map<RequestMappingInfo, HandlerMethod> liveMappings,
            ValidationAccumulator accumulator) {
        Map<RouteKey, List<LiveEndpoint>> grouped = new LinkedHashMap<>();
        if (liveMappings == null) {
            return grouped;
        }
        for (Map.Entry<RequestMappingInfo, HandlerMethod> mapping : liveMappings.entrySet()) {
            HandlerMethod handlerMethod = mapping.getValue();
            Set<String> routes = mapping.getKey().getPatternValues();
            if (routes.isEmpty()) {
                accumulator.excludedMappingCount++;
                continue;
            }
            boolean includedRoute = false;
            for (String route : routes) {
                String normalizedRoute = normalizeRoute(route);
                if (!isApplicationApiHandler(handlerMethod, normalizedRoute)) {
                    continue;
                }
                includedRoute = true;
                addLiveEndpoints(mapping.getKey(), normalizedRoute, handlerMethod, grouped, accumulator);
            }
            if (!includedRoute) {
                accumulator.excludedMappingCount++;
            }
        }
        return grouped;
    }

    private static void addLiveEndpoints(RequestMappingInfo mapping,
                                         String normalizedRoute,
                                         HandlerMethod handlerMethod,
                                         Map<RouteKey, List<LiveEndpoint>> grouped,
                                         ValidationAccumulator accumulator) {
        Set<org.springframework.web.bind.annotation.RequestMethod> methods =
                mapping.getMethodsCondition().getMethods();
        if (methods.isEmpty()) {
            accumulator.applicationMappingCount++;
            accumulator.violate(ViolationType.METHODLESS,
                    "application /api/** mapping requires explicit HTTP method");
            return;
        }
        for (org.springframework.web.bind.annotation.RequestMethod method : methods) {
            addLiveEndpoint(method.name(), normalizedRoute, handlerMethod, grouped, accumulator);
        }
    }

    private static void addLiveEndpoint(String httpMethod,
                                        String normalizedRoute,
                                        HandlerMethod handlerMethod,
                                        Map<RouteKey, List<LiveEndpoint>> grouped,
                                        ValidationAccumulator accumulator) {
        RouteKey key = new RouteKey(httpMethod, normalizedRoute);
        LiveEndpoint endpoint = new LiveEndpoint(httpMethod, normalizedRoute, handlerMethod);
        List<LiveEndpoint> sameKey = grouped.computeIfAbsent(key, ignored -> new ArrayList<>());
        if (!sameKey.isEmpty()) {
            accumulator.violate(ViolationType.DUPLICATE,
                    "duplicate live mapping key " + key.display());
        }
        sameKey.add(endpoint);
        accumulator.applicationMappingCount++;
    }

    private static boolean isApplicationApiHandler(HandlerMethod handlerMethod, String route) {
        return handlerMethod != null
                && handlerMethod.getBeanType() != null
                && handlerMethod.getBeanType().getName().startsWith(APPLICATION_PACKAGE_PREFIX)
                && route.startsWith("/api/")
                && !isExcludedRoute(route);
    }

    private static boolean isExcludedRoute(String route) {
        return route.startsWith("/error") || route.startsWith("/actuator") || route.startsWith("/static");
    }

    private static List<EndpointMetadata> standardMetadata() {
        return List.of(
                standard("POST", "/api/auth/login", AuthController.class, "login", "AUTH", "LOGIN"),
                standard("POST", "/api/auth/logout", AuthController.class, "logout", "AUTH", "LOGOUT"),
                standard("GET", "/api/auth/me", AuthController.class, "me", "AUTH", "ME"),
                standard("POST", "/api/daily-reports", DailyReportCommandController.class,
                        "create", "DAILY_REPORT", "CREATE"),
                standard("PUT", "/api/daily-reports/{reportId}", DailyReportCommandController.class,
                        "update", "DAILY_REPORT", "UPDATE"),
                standard("GET", "/api/daily-reports", DailyReportSearchController.class,
                        "search", "DAILY_REPORT", "SEARCH"),
                standard("GET", "/api/daily-reports/{reportId}", DailyReportSearchController.class,
                        "get", "DAILY_REPORT", "DETAIL"),
                standard("GET", "/api/daily-reports/pending-approvals", DailyReportPendingApprovalController.class,
                        "pendingApprovals", "DAILY_REPORT", "PENDING_APPROVALS"),
                standard("POST", "/api/daily-reports/{reportId}/submit", DailyReportSubmissionController.class,
                        "submit", "DAILY_REPORT", "SUBMIT"),
                standard("POST", "/api/daily-reports/{reportId}/resubmit", DailyReportSubmissionController.class,
                        "resubmit", "DAILY_REPORT", "RESUBMIT"),
                standard("POST", "/api/daily-reports/{reportId}/approve", DailyReportApprovalController.class,
                        "approve", "DAILY_REPORT", "APPROVE"),
                standard("POST", "/api/daily-reports/{reportId}/reject", DailyReportApprovalController.class,
                        "reject", "DAILY_REPORT", "REJECT"),
                standard("GET", "/api/master/projects", MasterController.class,
                        "projects", "MASTER", "PROJECTS"),
                standard("GET", "/api/master/work-categories", MasterController.class,
                        "workCategories", "MASTER", "WORK_CATEGORIES"),
                standard("GET", "/api/master/holiday-types", MasterController.class,
                        "holidayTypes", "MASTER", "HOLIDAY_TYPES"),
                standard("GET", "/api/master/groups", MasterController.class,
                        "groups", "MASTER", "GROUPS"),
                standard("GET", "/api/master/messages", MessageCatalogController.class,
                        "messages", "MASTER", "MESSAGES"),
                standard("GET", "/api/monthly-summaries", MonthlySummaryController.class,
                        "monthlySummary", "MONTHLY_SUMMARY", "MONTHLY_SUMMARY"));
    }

    private static EndpointMetadata standard(String httpMethod, String route, Class<?> beanType,
                                             String methodName, String feature, String useCase) {
        Method method = Arrays.stream(beanType.getMethods())
                .filter(candidate -> candidate.getName().equals(methodName))
                .findFirst()
                .orElseThrow(() -> new IllegalStateException(
                        "Endpoint metadata method is missing: " + beanType.getName() + "#" + methodName));
        return new EndpointMetadata(httpMethod, route, beanType, method, feature, useCase);
    }

    private static String methodSignature(Method method) {
        if (method == null) {
            return "";
        }
        return method.getDeclaringClass().getName() + "#" + method.getName()
                + Arrays.stream(method.getParameterTypes())
                        .map(Class::getName)
                        .collect(java.util.stream.Collectors.joining(",", "(", ")"));
    }

    /**
     * Controller methodを同一性比較するための値。
     */
    public record HandlerMethodIdentity(Class<?> beanType, String methodSignature) {
        public HandlerMethodIdentity(Class<?> beanType, Method method) {
            this(beanType, EndpointMetadataRegistry.methodSignature(method));
        }

        public static HandlerMethodIdentity from(HandlerMethod handlerMethod) {
            return handlerMethod == null ? null
                    : new HandlerMethodIdentity(handlerMethod.getBeanType(), handlerMethod.getMethod());
        }
    }

    /**
     * HTTP method、normalized route、HandlerMethod、観測メタデータの中央定義。
     */
    public record EndpointMetadata(String httpMethod, String normalizedRoute,
                                   Class<?> beanType, String methodSignature,
                                   String feature, String useCase) {
        public EndpointMetadata {
            httpMethod = normalizeHttpMethod(httpMethod);
            normalizedRoute = normalizeRoute(normalizedRoute);
            methodSignature = methodSignature == null ? "" : methodSignature;
            feature = feature == null || feature.isBlank() ? RequestContext.UNKNOWN : feature;
            useCase = useCase == null || useCase.isBlank() ? RequestContext.UNKNOWN : useCase;
        }

        public EndpointMetadata(String httpMethod, String normalizedRoute, Class<?> beanType,
                                Method method, String feature, String useCase) {
            this(httpMethod, normalizedRoute, beanType,
                    EndpointMetadataRegistry.methodSignature(method), feature, useCase);
        }

        public EndpointMetadata(String httpMethod, String normalizedRoute, HandlerMethod handlerMethod,
                                String feature, String useCase) {
            this(httpMethod, normalizedRoute,
                    handlerMethod == null ? null : handlerMethod.getBeanType(),
                    handlerMethod == null ? "" : EndpointMetadataRegistry.methodSignature(handlerMethod.getMethod()),
                    feature, useCase);
        }

        public HandlerMethodIdentity handlerMethod() {
            return beanType == null || methodSignature.isBlank() ? null
                    : new HandlerMethodIdentity(beanType, methodSignature);
        }

        public boolean matches(HandlerMethod actualHandlerMethod) {
            return actualHandlerMethod != null
                    && Objects.equals(beanType, actualHandlerMethod.getBeanType())
                    && Objects.equals(methodSignature,
                            EndpointMetadataRegistry.methodSignature(actualHandlerMethod.getMethod()));
        }
    }

    /**
     * live mappingまたはregistryをHTTP methodとnormalized routeでまとめる比較キー。
     */
    public record RouteKey(String httpMethod, String normalizedRoute) {
        public RouteKey {
            httpMethod = normalizeHttpMethod(httpMethod);
            normalizedRoute = normalizeRoute(normalizedRoute);
        }

        public String display() {
            return httpMethod + " " + normalizedRoute;
        }
    }

    /**
     * 実Spring mappingから展開した一件の対象endpoint。
     */
    public record LiveEndpoint(String httpMethod, String normalizedRoute, HandlerMethod handlerMethod) {
        public LiveEndpoint {
            httpMethod = normalizeHttpMethod(httpMethod);
            normalizedRoute = normalizeRoute(normalizedRoute);
        }
    }

    /**
     * mapping列挙結果を契約テストで観測するためのsnapshot。
     */
    public record LiveMappingSnapshot(List<LiveEndpoint> endpoints,
                                      int applicationMappingCount,
                                      int excludedMappingCount,
                                      List<Violation> violations) {
        public LiveMappingSnapshot {
            endpoints = List.copyOf(endpoints);
            violations = List.copyOf(violations);
        }
    }

    /**
     * registryとlive mappingの比較結果。
     */
    public record ValidationReport(List<Violation> violations,
                                   int registryEntryCount,
                                   int applicationMappingCount,
                                   int excludedMappingCount) {
        public ValidationReport {
            violations = List.copyOf(violations);
        }

        public boolean isValid() {
            return violations.isEmpty();
        }

        public long violationCount(ViolationType type) {
            return violations.stream().filter(violation -> violation.type() == type).count();
        }

        public boolean hasMessage(String message) {
            return violations.stream().anyMatch(violation -> violation.message().equals(message));
        }
    }

    /**
     * live mappingとregistryの不一致をSpring起動失敗へ接続する例外。
     */
    public static final class EndpointMetadataValidationException extends IllegalStateException {
        private static final long serialVersionUID = 1L;

        public EndpointMetadataValidationException() {
            super("Endpoint metadata registry validation failed");
        }
    }

    /**
     * 検証で検出した一件の違反。
     */
    public record Violation(ViolationType type, String message) {
    }

    /**
     * PF-OBS-001で区別する違反種別。
     */
    public enum ViolationType {
        UNKNOWN_METADATA,
        MISSING_HANDLER_METHOD,
        ORPHAN,
        DUPLICATE,
        MISMATCH,
        METHODLESS
    }

    private static final class ValidationAccumulator {
        private final List<Violation> violations = new ArrayList<>();
        private int applicationMappingCount;
        private int excludedMappingCount;

        private void violate(ViolationType type, String message) {
            violations.add(new Violation(type, message));
        }

        private List<Violation> violations() {
            return List.copyOf(violations);
        }

        private ValidationReport report(int registryEntryCount) {
            return new ValidationReport(violations(), registryEntryCount,
                    applicationMappingCount, excludedMappingCount);
        }
    }
}

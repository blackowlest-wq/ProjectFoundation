package com.example.dailyreport.observability;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.mock;

import com.example.dailyreport.auth.AuthController;
import com.example.dailyreport.master.MasterController;
import com.example.dailyreport.master.MessageCatalogController;
import com.example.dailyreport.monthlysummary.MonthlySummaryController;
import com.example.framework.FrameworkController;
import java.lang.reflect.Constructor;
import java.lang.reflect.Method;
import java.util.Arrays;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.stream.Collectors;
import org.springframework.beans.factory.config.BeanDefinition;
import org.junit.jupiter.api.Test;
import org.springframework.context.annotation.AnnotatedBeanDefinitionReader;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.ClassPathScanningCandidateComponentProvider;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.type.filter.AnnotationTypeFilter;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.mock.web.MockServletContext;
import org.springframework.util.ClassUtils;
import org.springframework.web.context.support.GenericWebApplicationContext;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestMethod;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.method.HandlerMethod;
import org.springframework.web.servlet.config.annotation.EnableWebMvc;
import org.springframework.web.servlet.mvc.method.RequestMappingInfo;
import org.springframework.web.servlet.mvc.method.annotation.RequestMappingHandlerMapping;

class EndpointMetadataRegistryContractTest {
    @Test
    void tcPfl019EnumeratesLiveMappings() {
        try (GenericWebApplicationContext context = productionControllerContext()) {
            EndpointMetadataRegistry registry = new EndpointMetadataRegistry(
                    context.getBean(RequestMappingHandlerMapping.class));

            EndpointMetadataRegistry.ValidationReport report = registry.validateLiveMappings();

            assertThat(report.isValid()).isTrue();
            assertThat(report.applicationMappingCount()).isEqualTo(18);
            assertThat(report.registryEntryCount()).isEqualTo(18);
            assertThat(report.excludedMappingCount()).isZero();
            assertThat(registry.entries()).allSatisfy(metadata -> {
                assertThat(metadata.feature()).isNotEqualTo(RequestContext.UNKNOWN);
                assertThat(metadata.useCase()).isNotEqualTo(RequestContext.UNKNOWN);
            });
        }
    }

    @Test
    void tcPfl034NormalizesHttpMethod() {
        assertThat(EndpointMetadataRegistry.normalizeHttpMethod(" get ")).isEqualTo("GET");
    }

    @Test
    void tcPfl035NormalizesLeadingSlash() {
        assertThat(EndpointMetadataRegistry.normalizeRoute("api/master/groups"))
                .isEqualTo("/api/master/groups");
    }

    @Test
    void tcPfl036NormalizesPathVariable() {
        assertThat(EndpointMetadataRegistry.normalizeRoute("/api/reports/{id:[^/]+}"))
                .isEqualTo("/api/reports/{id}");
    }

    @Test
    void tcPfl037SeparatesHttpMethods() {
        try (GenericWebApplicationContext context = contextWith(MultiMethodController.class)) {
            RequestMappingHandlerMapping mapping = context.getBean(RequestMappingHandlerMapping.class);
            EndpointMetadataRegistry.LiveMappingSnapshot snapshot = new EndpointMetadataRegistry(
                    List.of()).snapshot(mapping.getHandlerMethods());

            assertThat(snapshot.violations()).isEmpty();
            assertThat(snapshot.applicationMappingCount()).isEqualTo(2);
            assertThat(snapshot.endpoints()).extracting(EndpointMetadataRegistry.LiveEndpoint::httpMethod)
                    .containsExactlyInAnyOrder("GET", "POST");
            assertThat(snapshot.endpoints()).extracting(EndpointMetadataRegistry.LiveEndpoint::normalizedRoute)
                    .containsOnly("/api/reports");
        }
    }

    @Test
    void tcPfl058LiveMappingsUseCentralRegistry() {
        try (GenericWebApplicationContext context = productionControllerContext()) {
            EndpointMetadataRegistry registry = new EndpointMetadataRegistry(
                    context.getBean(RequestMappingHandlerMapping.class));

            EndpointMetadataRegistry.ValidationReport report = registry.validateLiveMappings();

            assertThat(report.isValid()).isTrue();
            assertThat(report.applicationMappingCount()).isEqualTo(18);
            assertThat(report.registryEntryCount()).isEqualTo(18);
            assertThat(registry.entries())
                    .allSatisfy(metadata -> assertThat(metadata.feature()).isNotEqualTo(RequestContext.UNKNOWN));
            assertThat(registry.entries())
                    .allSatisfy(metadata -> assertThat(metadata.useCase()).isNotEqualTo(RequestContext.UNKNOWN));
        }
    }

    @Test
    void tcPfl059RejectsUnknownMetadata() throws Exception {
        HandlerMethod handler = handlerMethod(MetadataController.class, "known");
        EndpointMetadataRegistry registry = new EndpointMetadataRegistry(List.of(
                new EndpointMetadataRegistry.EndpointMetadata(
                        "GET", "/api/metadata", handler, RequestContext.UNKNOWN, "KNOWN")));

        EndpointMetadataRegistry.ValidationReport report = registry.validate(singleMapping(
                "/api/metadata", RequestMethod.GET, handler));

        assertThat(report.violationCount(EndpointMetadataRegistry.ViolationType.UNKNOWN_METADATA)).isEqualTo(1);
        assertThat(report.hasMessage("metadata feature must not be UNKNOWN")).isTrue();
    }

    @Test
    void tcPfl060RequiresHandlerMethod() {
        EndpointMetadataRegistry registry = new EndpointMetadataRegistry(List.of(
                new EndpointMetadataRegistry.EndpointMetadata(
                        "GET", "/api/metadata", (HandlerMethod) null, "TEST", "KNOWN")));

        EndpointMetadataRegistry.ValidationReport report = registry.validate(Map.of());

        assertThat(report.hasMessage("HandlerMethod is required")).isTrue();
    }

    @Test
    void tcPfl061RejectsOrphanEntry() throws Exception {
        HandlerMethod handler = handlerMethod(MetadataController.class, "known");
        EndpointMetadataRegistry registry = new EndpointMetadataRegistry(List.of(
                new EndpointMetadataRegistry.EndpointMetadata(
                        "GET", "/api/orphan", handler, "TEST", "KNOWN")));

        EndpointMetadataRegistry.ValidationReport report = registry.validate(Map.of());

        assertThat(report.hasMessage("orphan EndpointMetadataRegistry entry")).isTrue();
    }

    @Test
    void tcPfl062RejectsDuplicateKey() throws Exception {
        HandlerMethod handler = handlerMethod(MetadataController.class, "known");
        EndpointMetadataRegistry.EndpointMetadata entry = new EndpointMetadataRegistry.EndpointMetadata(
                "GET", "/api/duplicate", handler, "TEST", "KNOWN");
        EndpointMetadataRegistry registry = new EndpointMetadataRegistry(List.of(entry, entry));

        EndpointMetadataRegistry.ValidationReport report = registry.validate(Map.of());

        assertThat(report.hasMessage("duplicate registry key GET /api/duplicate")).isTrue();
    }

    @Test
    void tcPfl063ConsumesCentralRegistry() throws Exception {
        EndpointMetadataRegistry registry = EndpointMetadataRegistry.standard();
        HandlerMethod handler = handlerMethod(MasterController.class, "groups",
                com.example.dailyreport.auth.AuthenticatedUser.class);
        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/api/master/groups");

        new RequestMetadataInterceptor(registry).preHandle(request, new MockHttpServletResponse(), handler);

        assertThat(request.getAttribute(RequestContext.FEATURE_ATTRIBUTE)).isEqualTo("MASTER");
        assertThat(request.getAttribute(RequestContext.USE_CASE_ATTRIBUTE)).isEqualTo("GROUPS");
        assertThat(RequestContext.featureForPath("/api/master/groups")).isEqualTo("MASTER");
        assertThat(RequestContext.useCaseForPath("GET", "/api/master/groups")).isEqualTo("GROUPS");
    }

    @Test
    void tcPfl073ActualRoutes() {
        try (GenericWebApplicationContext context = productionControllerContext()) {
            EndpointMetadataRegistry registry = new EndpointMetadataRegistry(
                    context.getBean(RequestMappingHandlerMapping.class));
            Set<String> routes = registry.entries().stream()
                    .map(entry -> entry.httpMethod() + " " + entry.normalizedRoute())
                    .collect(Collectors.toSet());

            assertThat(routes).contains("GET /api/master/groups", "GET /api/master/messages");
            assertThat(registry.validateLiveMappings().isValid()).isTrue();
        }
    }

    @Test
    void tcPfl078GroupsBaseline() throws Exception {
        HandlerMethod handler = handlerMethod(MasterController.class, "groups",
                com.example.dailyreport.auth.AuthenticatedUser.class);

        assertThat(EndpointMetadataRegistry.standard().lookup(
                "GET", "/api/master/groups", handler)).isPresent();
    }

    @Test
    void tcPfl079MessagesBaseline() throws Exception {
        HandlerMethod handler = handlerMethod(MessageCatalogController.class, "messages", String.class);

        assertThat(EndpointMetadataRegistry.standard().lookup(
                "GET", "/api/master/messages", handler)).isPresent();
    }

    @Test
    void tcPfl102ExcludesFrameworkMapping() {
        try (GenericWebApplicationContext context = contextWith(FrameworkController.class)) {
            EndpointMetadataRegistry.LiveMappingSnapshot snapshot = new EndpointMetadataRegistry(List.of())
                    .snapshot(context.getBean(RequestMappingHandlerMapping.class).getHandlerMethods());

            assertThat(snapshot.applicationMappingCount()).isZero();
            assertThat(snapshot.excludedMappingCount()).isEqualTo(1);
            assertThat(snapshot.violations()).isEmpty();
        }
    }

    @Test
    void tcPfl103ExcludesNonApiApplicationHandler() {
        try (GenericWebApplicationContext context = contextWith(InternalController.class)) {
            EndpointMetadataRegistry.LiveMappingSnapshot snapshot = new EndpointMetadataRegistry(List.of())
                    .snapshot(context.getBean(RequestMappingHandlerMapping.class).getHandlerMethods());

            assertThat(snapshot.applicationMappingCount()).isZero();
            assertThat(snapshot.excludedMappingCount()).isEqualTo(1);
            assertThat(snapshot.violations()).isEmpty();
        }
    }

    @Test
    void tcPfl104RejectsMethodlessApplicationApi() {
        try (GenericWebApplicationContext context = contextWith(MethodlessController.class)) {
            EndpointMetadataRegistry.LiveMappingSnapshot snapshot = new EndpointMetadataRegistry(List.of())
                    .snapshot(context.getBean(RequestMappingHandlerMapping.class).getHandlerMethods());

            assertThat(snapshot.applicationMappingCount()).isEqualTo(1);
            assertThat(snapshot.violations()).hasSize(1);
            assertThat(snapshot.violations())
                    .extracting(EndpointMetadataRegistry.Violation::message)
                    .containsExactly("application /api/** mapping requires explicit HTTP method");
        }
    }

    @Test
    void tcPfl105ExpandsExplicitMethods() {
        try (GenericWebApplicationContext context = contextWith(MultiMethodController.class)) {
            RequestMappingHandlerMapping mapping = context.getBean(RequestMappingHandlerMapping.class);
            HandlerMethod handler = mapping.getHandlerMethods().values().stream()
                    .filter(candidate -> candidate.getBeanType() == MultiMethodController.class)
                    .findFirst()
                    .orElseThrow();
            EndpointMetadataRegistry registry = new EndpointMetadataRegistry(List.of(
                    new EndpointMetadataRegistry.EndpointMetadata(
                            "GET", "/api/reports", handler, "TEST", "GET_REPORTS"),
                    new EndpointMetadataRegistry.EndpointMetadata(
                            "POST", "/api/reports", handler, "TEST", "POST_REPORTS")));

            EndpointMetadataRegistry.ValidationReport report = registry.validate(mapping.getHandlerMethods());
            Set<EndpointMetadataRegistry.RouteKey> keys = registry.entries().stream()
                    .map(entry -> new EndpointMetadataRegistry.RouteKey(entry.httpMethod(), entry.normalizedRoute()))
                    .collect(Collectors.toSet());
            long unknownMetadataCount = registry.entries().stream()
                    .filter(entry -> RequestContext.UNKNOWN.equals(entry.feature())
                            || RequestContext.UNKNOWN.equals(entry.useCase()))
                    .count();

            assertThat(report.isValid()).isTrue();
            assertThat(report.applicationMappingCount()).isEqualTo(2);
            assertThat(report.registryEntryCount()).isEqualTo(2);
            assertThat(registry.entries()).hasSize(2);
            assertThat(keys).containsExactlyInAnyOrder(
                    new EndpointMetadataRegistry.RouteKey("GET", "/api/reports"),
                    new EndpointMetadataRegistry.RouteKey("POST", "/api/reports"));
            assertThat(unknownMetadataCount).isZero();
            assertThat(report.violationCount(EndpointMetadataRegistry.ViolationType.UNKNOWN_METADATA)).isZero();
        }
    }

    @Test
    void tcPfl130SpringLifecycleFailsWhenLiveMappingIsNotRegistered() {
        try (GenericWebApplicationContext context = productionControllerContextWithRegistry(
                UnregisteredController.class)) {
            assertThatThrownBy(context::refresh)
                    .isInstanceOf(EndpointMetadataRegistry.EndpointMetadataValidationException.class)
                    .hasMessage("Endpoint metadata registry validation failed")
                    .hasMessageNotContaining("/api/unregistered");
        }
    }

    @Test
    void tcPfl131SpringLifecycleSucceedsWhenLiveMappingsMatch() {
        try (GenericWebApplicationContext context = productionControllerContextWithRegistry()) {
            context.refresh();

            EndpointMetadataRegistry registry = context.getBean(EndpointMetadataRegistry.class);
            assertThat(registry.lastValidation()).isPresent()
                    .get()
                    .extracting(EndpointMetadataRegistry.ValidationReport::isValid)
                    .isEqualTo(true);
        }
    }

    /**
     * Main classpathのControllerをSpringの通常スキャンと同じannotation条件で登録する。
     * 新しい未登録Controllerが追加されると、live mappingとregistryの比較でDが失敗する。
     */
    private static GenericWebApplicationContext productionControllerContext() {
        GenericWebApplicationContext context = newMvcContext();
        registerProductionControllers(context);
        context.refresh();
        return context;
    }

    private static GenericWebApplicationContext productionControllerContextWithRegistry(
            Class<?>... additionalControllerTypes) {
        GenericWebApplicationContext context = newMvcContext();
        registerProductionControllers(context);
        Arrays.stream(additionalControllerTypes)
                .forEach(controllerType -> registerController(context, controllerType));
        context.registerBean(EndpointMetadataRegistry.class);
        return context;
    }

    private static void registerProductionControllers(GenericWebApplicationContext context) {
        ClassPathScanningCandidateComponentProvider scanner =
                new ClassPathScanningCandidateComponentProvider(false);
        scanner.addIncludeFilter(new AnnotationTypeFilter(RestController.class));
        scanner.findCandidateComponents(EndpointMetadataRegistry.APPLICATION_PACKAGE_PREFIX).stream()
                .map(BeanDefinition::getBeanClassName)
                .filter(Objects::nonNull)
                .filter(className -> !className.contains("$"))
                .map(className -> ClassUtils.resolveClassName(className,
                        EndpointMetadataRegistryContractTest.class.getClassLoader()))
                .forEach(controllerType -> registerController(context, controllerType));
    }

    private static <T> void registerController(GenericWebApplicationContext context, Class<T> controllerType) {
        Arrays.stream(controllerType.getDeclaredConstructors())
                .flatMap(constructor -> Arrays.stream(constructor.getParameterTypes()))
                .distinct()
                .filter(dependencyType -> !context.containsBean(dependencyType.getName()))
                .forEach(dependencyType -> registerMock(context, dependencyType));
        context.registerBean(controllerType.getName(), controllerType,
                () -> instantiateController(controllerType, context));
    }

    private static <T> void registerMock(GenericWebApplicationContext context, Class<T> dependencyType) {
        context.registerBean(dependencyType.getName(), dependencyType, () -> mock(dependencyType));
    }

    private static <T> T instantiateController(Class<T> controllerType,
                                                GenericWebApplicationContext context) {
        Constructor<?> constructor = Arrays.stream(controllerType.getDeclaredConstructors())
                .findFirst()
                .orElseThrow(() -> new IllegalStateException("Controller constructor is missing: " + controllerType));
        Object[] dependencies = Arrays.stream(constructor.getParameterTypes())
                .map(context::getBean)
                .toArray();
        try {
            constructor.setAccessible(true);
            return controllerType.cast(constructor.newInstance(dependencies));
        } catch (ReflectiveOperationException exception) {
            throw new IllegalStateException("Controller could not be constructed: " + controllerType, exception);
        }
    }

    private static GenericWebApplicationContext contextWith(Class<?>... controllerTypes) {
        GenericWebApplicationContext context = newMvcContext();
        for (Class<?> controllerType : controllerTypes) {
            context.registerBean(controllerType);
        }
        context.refresh();
        return context;
    }

    private static GenericWebApplicationContext newMvcContext() {
        GenericWebApplicationContext context = new GenericWebApplicationContext(new MockServletContext());
        new AnnotatedBeanDefinitionReader(context).register(MvcConfig.class);
        return context;
    }

    private static HandlerMethod handlerMethod(Class<?> type, String methodName, Class<?>... parameterTypes)
            throws Exception {
        Object controller = controllerInstance(type);
        Method method = type.getMethod(methodName, parameterTypes);
        return new HandlerMethod(controller, method);
    }

    private static Object controllerInstance(Class<?> type) throws Exception {
        if (type == MasterController.class) {
            return new MasterController(null, null);
        }
        if (type == MessageCatalogController.class) {
            return new MessageCatalogController(null);
        }
        return type.getDeclaredConstructor().newInstance();
    }

    private static Map<RequestMappingInfo, HandlerMethod> singleMapping(
            String route, RequestMethod requestMethod, HandlerMethod handler) {
        return Map.of(RequestMappingInfo.paths(route).methods(requestMethod).build(), handler);
    }

    @Configuration(proxyBeanMethods = false)
    @EnableWebMvc
    static class MvcConfig {
        @Bean
        String marker() {
            return "contract";
        }
    }

    @RestController
    static class MultiMethodController {
        @RequestMapping(path = "/api/reports", method = {RequestMethod.GET, RequestMethod.POST})
        public void reports() {
        }
    }

    @RestController
    static class MetadataController {
        public void known() {
        }
    }

    @RestController
    static class InternalController {
        @GetMapping("/internal/health")
        public void health() {
        }
    }

    @RestController
    static class MethodlessController {
        @RequestMapping("/api/reports")
        public void reports() {
        }
    }

    @RestController
    static class UnregisteredController {
        @GetMapping("/api/unregistered")
        public void unregistered() {
        }
    }
}

package com.example.dailyreport.master;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.springframework.dao.DataAccessResourceFailureException;

class MessageCatalogServiceTest {
    @Test
    void resolveReturnsDatabaseTextForDefaultLocale() {
        MessageCatalogRepository repository = mock(MessageCatalogRepository.class);
        when(repository.findAll("ja-JP")).thenReturn(Map.of("sample.message", "DB文言"));
        MessageCatalogService service = service(repository, Map.of("sample.message", "ソース文言"));

        assertThat(service.resolve("sample.message", "ソース文言")).isEqualTo("DB文言");
    }

    @Test
    void resolveReturnsSourceFallbackWhenDatabaseDoesNotContainKey() {
        MessageCatalogRepository repository = mock(MessageCatalogRepository.class);
        when(repository.findAll("ja-JP")).thenReturn(Map.of());
        MessageCatalogService service = service(repository, Map.of());

        assertThat(service.resolve("missing.message", "ソース文言")).isEqualTo("ソース文言");
    }

    @Test
    void ignoresUnknownOrBlankDatabaseMessages() {
        MessageCatalogRepository repository = mock(MessageCatalogRepository.class);
        when(repository.findAll("ja-JP")).thenReturn(Map.of(
                "known.message", "DB文言",
                "unknown.message", "未知キー",
                "blank.message", ""));
        MessageCatalogService service = service(repository, Map.of("known.message", "ソース文言"));

        assertThat(service.messages("ja-JP"))
                .containsEntry("known.message", "DB文言")
                .doesNotContainKeys("unknown.message", "blank.message");
    }

    @Test
    void resolveReturnsSourceFallbackWhenDatabaseIsUnavailable() {
        MessageCatalogRepository repository = mock(MessageCatalogRepository.class);
        when(repository.findAll("ja-JP"))
                .thenThrow(new DataAccessResourceFailureException("database unavailable"));
        MessageCatalogService service = service(repository, Map.of());

        assertThat(service.resolve("missing.message", "ソース文言")).isEqualTo("ソース文言");
    }

    @Test
    void messagesSupportsLocaleAndIncludesSourceDefaults() {
        MessageCatalogRepository repository = mock(MessageCatalogRepository.class);
        when(repository.findAll("en-US")).thenReturn(Map.of("sample.message", "DB text"));
        MessageCatalogService service = service(repository, Map.of(
                "sample.message", "Source text", "fallback.message", "Fallback"));

        assertThat(service.messages("en-US"))
                .containsEntry("sample.message", "DB text")
                .containsEntry("fallback.message", "Fallback");
    }

    @Test
    void expiredCacheReloadsDatabaseText() {
        MessageCatalogRepository repository = mock(MessageCatalogRepository.class);
        when(repository.findAll("ja-JP"))
                .thenReturn(Map.of("sample.message", "初回文言"))
                .thenReturn(Map.of("sample.message", "更新文言"));
        MutableClock clock = new MutableClock();
        MessageCatalogService service = new MessageCatalogService(
                repository, clock, Duration.ofMinutes(5), Map.of("sample.message", "fallback"));

        assertThat(service.resolve("sample.message", "fallback")).isEqualTo("初回文言");
        clock.advance(Duration.ofMinutes(5));
        assertThat(service.resolve("sample.message", "fallback")).isEqualTo("更新文言");
    }

    private MessageCatalogService service(MessageCatalogRepository repository, Map<String, String> defaults) {
        return new MessageCatalogService(
                repository,
                Clock.fixed(Instant.parse("2026-08-04T00:00:00Z"), ZoneOffset.UTC),
                Duration.ofMinutes(5),
                defaults);
    }

    private static final class MutableClock extends Clock {
        private Instant current = Instant.parse("2026-08-04T00:00:00Z");

        @Override
        public ZoneOffset getZone() {
            return ZoneOffset.UTC;
        }

        @Override
        public Clock withZone(java.time.ZoneId zone) {
            return this;
        }

        @Override
        public Instant instant() {
            return current;
        }

        void advance(Duration duration) {
            current = current.plus(duration);
        }
    }
}

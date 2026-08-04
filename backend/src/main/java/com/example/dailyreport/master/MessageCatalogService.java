/**
 * DBメッセージを短時間キャッシュし、DB障害時は直前キャッシュまたはソース既定値へフォールバックする。
 */
package com.example.dailyreport.master;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.dao.DataAccessException;
import org.springframework.stereotype.Service;

@Service
public class MessageCatalogService {
    private static final Logger LOGGER = LoggerFactory.getLogger(MessageCatalogService.class);
    private final MessageCatalogRepository repository;
    private final Clock clock;
    private final Duration ttl;
    private final Map<String, String> defaults;
    private final Map<String, CacheEntry> cache = new ConcurrentHashMap<>();

    @Autowired
    public MessageCatalogService(MessageCatalogRepository repository) {
        this(repository, Clock.systemUTC(), Duration.ofMinutes(5), MessageCatalogDefaults.defaults());
    }

    public MessageCatalogService(MessageCatalogRepository repository, Clock clock, Duration ttl,
                                 Map<String, String> defaults) {
        if (ttl.isNegative() || ttl.isZero()) {
            throw new IllegalArgumentException("Message catalog TTL must be positive.");
        }
        this.repository = repository;
        this.clock = clock;
        this.ttl = ttl;
        this.defaults = Map.copyOf(defaults);
    }

    /**
     * 既定ロケールの指定キーを解決する。キーが未登録・空の場合は呼び出し元の既定値を返す。
     */
    public String resolve(String key, String fallback) {
        return resolve(MessageCatalogDefaults.DEFAULT_LOCALE, key, fallback);
    }

    /**
     * 指定ロケールのキーを解決する。DB例外の詳細は呼び出し元へ返さない。
     */
    public String resolve(String locale, String key, String fallback) {
        if (key == null || key.isBlank()) {
            return fallback;
        }
        return messages(locale).getOrDefault(key, fallback);
    }

    /**
     * 指定ロケールのDB文言とソース既定値を統合して返す。
     */
    public Map<String, String> messages(String locale) {
        String normalizedLocale = normalizeLocale(locale);
        Instant now = clock.instant();
        CacheEntry current = cache.get(normalizedLocale);
        if (current != null && now.isBefore(current.loadedAt().plus(ttl))) {
            return current.messages();
        }

        try {
            Map<String, String> merged = new LinkedHashMap<>(defaults);
            repository.findAll(normalizedLocale).forEach((key, value) -> {
                // Why not: ソース未定義キーや空本文を採用すると、DB変更だけで未検証の表示契約を追加できるため無視する。
                if (defaults.containsKey(key) && value != null && !value.isBlank()) {
                    merged.put(key, value);
                }
            });
            Map<String, String> immutable = Map.copyOf(merged);
            cache.put(normalizedLocale, new CacheEntry(immutable, now));
            return immutable;
        } catch (DataAccessException exception) {
            LOGGER.warn("event=message_catalog.unavailable locale={} fallback=true", normalizedLocale);
            if (current != null) {
                return current.messages();
            }
            return defaults;
        }
    }

    private String normalizeLocale(String locale) {
        return locale == null || locale.isBlank() ? MessageCatalogDefaults.DEFAULT_LOCALE : locale;
    }

    private record CacheEntry(Map<String, String> messages, Instant loadedAt) {
    }
}

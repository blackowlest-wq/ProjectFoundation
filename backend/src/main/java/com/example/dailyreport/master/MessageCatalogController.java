/**
 * 認証済み画面が利用するメッセージカタログAPI。
 */
package com.example.dailyreport.master;

import java.util.Map;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class MessageCatalogController {
    private final MessageCatalogService messageCatalogService;

    public MessageCatalogController(MessageCatalogService messageCatalogService) {
        this.messageCatalogService = messageCatalogService;
    }

    @GetMapping("/api/master/messages")
    public MessageCatalogResponse messages(
            @RequestParam(defaultValue = MessageCatalogDefaults.DEFAULT_LOCALE) String locale) {
        String normalizedLocale = locale == null || locale.isBlank()
                ? MessageCatalogDefaults.DEFAULT_LOCALE
                : locale;
        return new MessageCatalogResponse(normalizedLocale, messageCatalogService.messages(normalizedLocale));
    }

    public record MessageCatalogResponse(String locale, Map<String, String> messages) {
        public MessageCatalogResponse {
            messages = Map.copyOf(messages);
        }
    }
}

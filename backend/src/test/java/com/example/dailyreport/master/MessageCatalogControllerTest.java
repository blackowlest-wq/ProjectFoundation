package com.example.dailyreport.master;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.util.Map;
import org.junit.jupiter.api.Test;

class MessageCatalogControllerTest {
    @Test
    void blankLocaleUsesDefaultLocale() {
        MessageCatalogService service = mock(MessageCatalogService.class);
        when(service.messages(MessageCatalogDefaults.DEFAULT_LOCALE)).thenReturn(Map.of("ui.loading", "読込中"));
        MessageCatalogController controller = new MessageCatalogController(service);

        MessageCatalogController.MessageCatalogResponse response = controller.messages(" ");

        assertThat(response.locale()).isEqualTo(MessageCatalogDefaults.DEFAULT_LOCALE);
        assertThat(response.messages()).containsEntry("ui.loading", "読込中");
        verify(service).messages(MessageCatalogDefaults.DEFAULT_LOCALE);
    }
}

package com.example.dailyreport.common;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.example.dailyreport.observability.RequestIdFilter;
import com.example.dailyreport.observability.RequestMetadataInterceptor;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.springframework.boot.test.system.CapturedOutput;
import org.springframework.boot.test.system.OutputCaptureExtension;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

@ExtendWith(OutputCaptureExtension.class)
class ApiExceptionHandlerTest {
    private MockMvc mockMvc;

    @BeforeEach
    void setUp() {
        mockMvc = MockMvcBuilders.standaloneSetup(new FailureController())
                .setControllerAdvice(new ApiExceptionHandler())
                .addFilters(new RequestIdFilter())
                .addInterceptors(new RequestMetadataInterceptor())
                .build();
    }

    @Test
    void returnsBusinessErrorWithCorrelatedRequestId() throws Exception {
        var result = mockMvc.perform(get("/test/business"))
                .andExpect(status().isConflict())
                .andExpect(header().exists("X-Request-Id"))
                .andExpect(jsonPath("$.code").value("BUSINESS_CONFLICT"))
                .andExpect(jsonPath("$.message").value("業務処理を完了できません。"))
                .andExpect(jsonPath("$.details").isArray())
                .andExpect(jsonPath("$.requestId").isNotEmpty())
                .andReturn();

        String headerRequestId = result.getResponse().getHeader("X-Request-Id");
        String bodyRequestId = result.getResponse().getContentAsString()
                .replaceAll(".*\"requestId\":\"([^\"]+)\".*", "$1");
        assertThat(bodyRequestId).isEqualTo(headerRequestId);
    }

    @Test
    void hidesUnexpectedExceptionDetailsAndLogsSystemFailure(CapturedOutput output) throws Exception {
        var result = mockMvc.perform(get("/test/system"))
                .andExpect(status().isInternalServerError())
                .andExpect(header().exists("X-Request-Id"))
                .andExpect(jsonPath("$.code").value("INTERNAL_SERVER_ERROR"))
                .andExpect(jsonPath("$.message").value("システムエラーが発生しました。"))
                .andExpect(jsonPath("$.details").isEmpty())
                .andExpect(jsonPath("$.requestId").isNotEmpty())
                .andReturn();

        assertThat(result.getResponse().getContentAsString()).doesNotContain("database password");
        assertThat(output).contains("event=system.unhandled_exception");
        assertThat(output).contains("IllegalStateException");
        assertThat(output).doesNotContain("database password must not be returned");
    }

    @Test
    void mapsMalformedJsonToBusinessInputError(CapturedOutput output) throws Exception {
        mockMvc.perform(post("/test/json")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("INVALID_REQUEST"))
                .andExpect(jsonPath("$.message").value("入力内容に誤りがあります。"))
                .andExpect(jsonPath("$.requestId").isNotEmpty());

        assertThat(output).contains("event=business.error");
        assertThat(output).contains("code=INVALID_REQUEST");
        assertThat(output).doesNotContain("event=system.unhandled_exception");
    }

    @RestController
    static class FailureController {
        @GetMapping("/test/business")
        String business() {
            throw new ApiException(HttpStatus.CONFLICT, "BUSINESS_CONFLICT", "業務処理を完了できません。");
        }

        @GetMapping("/test/system")
        String system() {
            throw new IllegalStateException("database password must not be returned");
        }

        @PostMapping("/test/json")
        String json(@RequestBody TestPayload payload) {
            return payload.value();
        }

        record TestPayload(String value) {
        }
    }
}

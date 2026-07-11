package com.example.dailyreport.auth;

import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.hasItem;
import static org.hamcrest.Matchers.not;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.csrf;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.mock.web.MockHttpSession;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
class AuthControllerTest {
    @Autowired
    MockMvc mockMvc;

    @Autowired
    ObjectMapper objectMapper;

    @Test
    void loginSucceedsAndMeReturnsCurrentUser() throws Exception {
        MvcResult result = mockMvc.perform(post("/api/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(loginJson("employee001", "password")))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.userId", equalTo("U001")))
                .andExpect(jsonPath("$.loginId", equalTo("employee001")))
                .andExpect(jsonPath("$.userName", equalTo("山田 太郎")))
                .andExpect(jsonPath("$.role", equalTo("EMPLOYEE")))
                .andExpect(jsonPath("$.passwordHash").doesNotExist())
                .andReturn();

        MockHttpSession session = (MockHttpSession) result.getRequest().getSession(false);
        mockMvc.perform(get("/api/auth/me").session(session))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.loginId", equalTo("employee001")));
    }

    @Test
    void loginSucceedsForAllRoles() throws Exception {
        assertLoginSucceeds("employee001", "EMPLOYEE");
        assertLoginSucceeds("manager001", "MANAGER");
        assertLoginSucceeds("admin001", "ADMIN");
    }

    @Test
    void loginRegeneratesSessionId() throws Exception {
        MockHttpSession anonymousSession = new MockHttpSession();
        String anonymousSessionId = anonymousSession.getId();

        MvcResult result = mockMvc.perform(post("/api/auth/login")
                        .session(anonymousSession)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(loginJson("employee001", "password")))
                .andExpect(status().isOk())
                .andReturn();

        MockHttpSession authenticatedSession = (MockHttpSession) result.getRequest().getSession(false);
        org.hamcrest.MatcherAssert.assertThat(authenticatedSession.getId(), not(equalTo(anonymousSessionId)));
    }

    @Test
    void loginFailsWithInvalidPassword() throws Exception {
        mockMvc.perform(post("/api/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(loginJson("employee001", "wrong")))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code", equalTo("AUTHENTICATION_FAILED")));
    }

    @Test
    void loginFailsWithUnknownLoginId() throws Exception {
        mockMvc.perform(post("/api/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(loginJson("unknown001", "password")))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code", equalTo("AUTHENTICATION_FAILED")));
    }

    @Test
    void meRequiresAuthentication() throws Exception {
        mockMvc.perform(get("/api/auth/me"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void logoutRequiresCsrfToken() throws Exception {
        MockHttpSession session = loginAs("manager001", "password");

        mockMvc.perform(post("/api/auth/logout").session(session))
                .andExpect(status().isForbidden());
    }

    @Test
    void logoutWithCsrfInvalidatesSession() throws Exception {
        MockHttpSession session = loginAs("manager001", "password");

        mockMvc.perform(post("/api/auth/logout").with(csrf()).session(session))
                .andExpect(status().isNoContent());

        mockMvc.perform(get("/api/auth/me").session(session))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void loginValidationRejectsTooLongLoginId() throws Exception {
        String tooLongLoginId = "a".repeat(81);
        mockMvc.perform(post("/api/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(loginJson(tooLongLoginId, "password")))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code", equalTo("VALIDATION_ERROR")))
                .andExpect(jsonPath("$.details[0].message", equalTo("ログインIDは80文字以内で入力してください。")));
    }

    @Test
    void loginValidationAcceptsMaxLengthLoginId() throws Exception {
        String maxLengthLoginId = "a".repeat(80);
        mockMvc.perform(post("/api/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(loginJson(maxLengthLoginId, "password")))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code", equalTo("AUTHENTICATION_FAILED")));
    }

    @Test
    void loginValidationRejectsTooLongPassword() throws Exception {
        String tooLongPassword = "a".repeat(101);
        mockMvc.perform(post("/api/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(loginJson("employee001", tooLongPassword)))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code", equalTo("VALIDATION_ERROR")))
                .andExpect(jsonPath("$.details[0].message", equalTo("パスワードは100文字以内で入力してください。")));
    }

    @Test
    void loginValidationRejectsNonAlphanumericLoginId() throws Exception {
        mockMvc.perform(post("/api/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(loginJson("employee_001", "password")))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code", equalTo("VALIDATION_ERROR")))
                .andExpect(jsonPath("$.details[*].message", hasItem("ログインIDは半角英数字で入力してください。")));
    }

    @Test
    void loginValidationRejectsNonAlphanumericPassword() throws Exception {
        mockMvc.perform(post("/api/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(loginJson("employee001", "pass-word")))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code", equalTo("VALIDATION_ERROR")))
                .andExpect(jsonPath("$.details[*].message", hasItem("パスワードは半角英数字で入力してください。")));
    }

    @Test
    void loginValidationAcceptsMaxLengthPassword() throws Exception {
        String maxLengthPassword = "a".repeat(100);
        mockMvc.perform(post("/api/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(loginJson("employee001", maxLengthPassword)))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code", equalTo("AUTHENTICATION_FAILED")));
    }

    @Test
    void loginValidationRejectsMissingAndBlankFields() throws Exception {
        mockMvc.perform(post("/api/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code", equalTo("VALIDATION_ERROR")));

        mockMvc.perform(post("/api/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(loginJson("", "")))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code", equalTo("VALIDATION_ERROR")));

        mockMvc.perform(post("/api/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(loginJson(" ", " ")))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code", equalTo("VALIDATION_ERROR")));
    }

    private MockHttpSession loginAs(String loginId, String password) throws Exception {
        MvcResult result = mockMvc.perform(post("/api/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(loginJson(loginId, password)))
                .andExpect(status().isOk())
                .andReturn();

        return (MockHttpSession) result.getRequest().getSession(false);
    }

    private String loginJson(String loginId, String password) throws Exception {
        return objectMapper.writeValueAsString(Map.of("loginId", loginId, "password", password));
    }

    private void assertLoginSucceeds(String loginId, String role) throws Exception {
        mockMvc.perform(post("/api/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(loginJson(loginId, "password")))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.loginId", equalTo(loginId)))
                .andExpect(jsonPath("$.role", equalTo(role)));
    }
}

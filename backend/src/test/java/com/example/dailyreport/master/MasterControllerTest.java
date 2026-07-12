package com.example.dailyreport.master;

import static com.example.dailyreport.support.MockMvcTestSupport.loginAs;
import static org.hamcrest.Matchers.equalTo;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.mock.web.MockHttpSession;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
class MasterControllerTest {
    @Autowired
    MockMvc mockMvc;

    @Autowired
    ObjectMapper objectMapper;

    @Test
    void protectedDailyReportApiRequiresLogin() throws Exception {
        mockMvc.perform(get("/api/master/projects"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void masterOptionsAreAvailableForLoggedInUser() throws Exception {
        MockHttpSession session = loginAs(mockMvc, objectMapper, "employee001");

        mockMvc.perform(get("/api/master/projects").session(session))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].projectId", equalTo("P001")));

        mockMvc.perform(get("/api/master/holiday-types").session(session))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].holidayType", equalTo("WORKDAY")));
    }
}

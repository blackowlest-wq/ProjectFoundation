package com.example.dailyreport.config;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.util.Map;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;

@SpringBootTest
@ActiveProfiles("oracle-test")
class OracleSafetyGuardIT {
    @Autowired
    JdbcTemplate jdbcTemplate;

    @Test
    void connectedDatabaseMatchesExpectedTestIdentity() {
        String expectedName = requiredEnvironment("DAILY_REPORT_DB_EXPECTED_NAME");
        String expectedService = requiredEnvironment("DAILY_REPORT_DB_EXPECTED_SERVICE");
        String expectedUser = requiredEnvironment("DAILY_REPORT_DB_EXPECTED_USER");

        Map<String, Object> identity = jdbcTemplate.queryForMap("""
                SELECT
                    SYS_CONTEXT('USERENV', 'DB_NAME') AS DB_NAME,
                    SYS_CONTEXT('USERENV', 'SERVICE_NAME') AS SERVICE_NAME,
                    SYS_CONTEXT('USERENV', 'SESSION_USER') AS SESSION_USER
                FROM dual
                """);

        assertIdentityMatches(expectedName, identity.get("DB_NAME"), "DB_NAME");
        assertIdentityMatches(expectedService, identity.get("SERVICE_NAME"), "SERVICE_NAME");
        assertIdentityMatches(expectedUser, identity.get("SESSION_USER"), "SESSION_USER");
    }

    private String requiredEnvironment(String name) {
        String value = System.getenv(name);
        if (value == null || value.isBlank()) {
            throw new IllegalStateException("Required Oracle identity environment variable is missing: " + name);
        }
        return value;
    }

    private void assertIdentityMatches(String expected, Object actual, String field) {
        assertTrue(expected.equalsIgnoreCase(String.valueOf(actual)),
                () -> field + " does not match the expected Oracle test identity.");
    }
}

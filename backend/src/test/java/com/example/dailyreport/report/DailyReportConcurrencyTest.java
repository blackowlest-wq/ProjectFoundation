package com.example.dailyreport.report;

import static com.example.dailyreport.report.support.DailyReportTestSupport.createReportId;
import static com.example.dailyreport.support.MockMvcTestSupport.loginAs;
import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.csrf;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;

import com.example.dailyreport.report.entity.DailyReportRepository;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.mock.web.MockHttpSession;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.jdbc.Sql;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
@Sql(statements = {
        "DELETE FROM daily_report_work_items",
        "DELETE FROM daily_reports"
}, executionPhase = Sql.ExecutionPhase.BEFORE_TEST_METHOD)
class DailyReportConcurrencyTest {
    @Autowired
    MockMvc mockMvc;

    @Autowired
    ObjectMapper objectMapper;

    @Autowired
    DailyReportRepository repository;

    @Autowired
    PlatformTransactionManager transactionManager;

    @Test
    void concurrentSubmitRechecksStatusAfterPriorTransactionCommits() throws Exception {
        MockHttpSession session = loginAs(mockMvc, objectMapper, "employee001");
        String reportId = createReportId(mockMvc, objectMapper, session, LocalDate.of(2026, 6, 16), 480);
        TransactionTemplate transactionTemplate = new TransactionTemplate(transactionManager);
        ExecutorService executor = Executors.newFixedThreadPool(2);
        CountDownLatch lockAcquired = new CountDownLatch(1);
        CountDownLatch releaseLock = new CountDownLatch(1);
        CountDownLatch secondTransactionStarted = new CountDownLatch(1);

        Future<?> holder = executor.submit(() -> transactionTemplate.executeWithoutResult(status -> {
            repository.findByReportIdAndEmployeeUserId(reportId, "U001").orElseThrow()
                    .submit(OffsetDateTime.parse("2026-06-16T10:00:00+09:00"));
            lockAcquired.countDown();
            await(releaseLock);
        }));

        try {
            assertThat(lockAcquired.await(5, TimeUnit.SECONDS)).isTrue();
            Future<MvcResult> waiter = executor.submit(() -> {
                secondTransactionStarted.countDown();
                return mockMvc.perform(post("/api/daily-reports/" + reportId + "/submit")
                                .with(csrf())
                                .session(session))
                        .andReturn();
            });
            assertThat(secondTransactionStarted.await(5, TimeUnit.SECONDS)).isTrue();

            assertThatThrownBy(() -> waiter.get(300, TimeUnit.MILLISECONDS))
                    .isInstanceOf(TimeoutException.class);

            releaseLock.countDown();
            MvcResult result = waiter.get(5, TimeUnit.SECONDS);
            assertThat(result.getResponse().getStatus()).isEqualTo(409);
            assertThat(objectMapper.readTree(result.getResponse().getContentAsString()).get("code").asText())
                    .isEqualTo("INVALID_STATUS");
        } finally {
            releaseLock.countDown();
            holder.get(5, TimeUnit.SECONDS);
            executor.shutdownNow();
        }
    }

    private static void await(CountDownLatch latch) {
        try {
            if (!latch.await(5, TimeUnit.SECONDS)) {
                throw new IllegalStateException("Timed out while holding the daily report lock.");
            }
        } catch (InterruptedException exception) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("Interrupted while holding the daily report lock.", exception);
        }
    }
}

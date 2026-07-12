package com.example.dailyreport.report;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.ApplicationContext;
import org.springframework.test.context.ActiveProfiles;

@SpringBootTest
@ActiveProfiles("test")
class DailyReportSeparationTest {
    @Autowired
    ApplicationContext applicationContext;

    @Test
    void separatedUseCaseBeansReplaceMixedDailyReportBeans() {
        assertThat(applicationContext.containsBean("dailyReportSearchController")).isTrue();
        assertThat(applicationContext.containsBean("dailyReportCommandController")).isTrue();
        assertThat(applicationContext.containsBean("dailyReportSubmissionController")).isTrue();
        assertThat(applicationContext.containsBean("dailyReportSearchService")).isTrue();
        assertThat(applicationContext.containsBean("dailyReportCommandService")).isTrue();
        assertThat(applicationContext.containsBean("dailyReportSubmissionService")).isTrue();
        assertThat(applicationContext.containsBean("dailyReportAccessPolicy")).isTrue();
        assertThat(applicationContext.containsBean("dailyReportController")).isFalse();
        assertThat(applicationContext.containsBean("dailyReportService")).isFalse();
    }
}

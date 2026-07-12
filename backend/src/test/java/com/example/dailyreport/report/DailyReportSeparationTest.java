package com.example.dailyreport.report;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.SpringBootConfiguration;
import org.springframework.boot.autoconfigure.EnableAutoConfiguration;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.ApplicationContext;
import org.springframework.context.annotation.Import;
import org.springframework.test.context.ActiveProfiles;
import com.example.dailyreport.auth.ManagerGroupPermissionRepository;
import com.example.dailyreport.master.MasterDataRepository;
import com.example.dailyreport.report.controller.DailyReportController;
import com.example.dailyreport.report.entity.DailyReportRepository;

@SpringBootTest(classes = DailyReportSeparationTest.TestApplication.class, properties = {
        "spring.autoconfigure.exclude=" +
                "org.springframework.boot.autoconfigure.jdbc.DataSourceAutoConfiguration," +
                "org.springframework.boot.autoconfigure.orm.jpa.HibernateJpaAutoConfiguration," +
                "org.springframework.boot.autoconfigure.data.jpa.JpaRepositoriesAutoConfiguration," +
                "org.springframework.boot.autoconfigure.jdbc.JdbcTemplateAutoConfiguration," +
                "org.springframework.boot.autoconfigure.sql.init.SqlInitializationAutoConfiguration"
})
@ActiveProfiles("test")
class DailyReportSeparationTest {
    @Autowired
    ApplicationContext applicationContext;

    @MockBean
    DailyReportRepository dailyReportRepository;

    @MockBean
    MasterDataRepository masterDataRepository;

    @MockBean
    ManagerGroupPermissionRepository managerGroupPermissionRepository;

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

    @SpringBootConfiguration
    @EnableAutoConfiguration
    @Import({DailyReportController.class, DailyReportService.class})
    static class TestApplication {
    }
}

package com.example.dailyreport.report;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.example.dailyreport.common.ApiException;
import java.time.LocalDate;
import org.junit.jupiter.api.Test;

class DailyReportDateRangeValidatorTest {
    @Test
    void acceptsDateRangeWithinLimit() {
        assertThatCode(() -> DailyReportDateRangeValidator.validate(
                LocalDate.of(2026, 1, 1), LocalDate.of(2026, 12, 31)))
                .doesNotThrowAnyException();
    }

    @Test
    void rejectsMissingDates() {
        assertThatThrownBy(() -> DailyReportDateRangeValidator.validate(null, null))
                .isInstanceOf(ApiException.class)
                .satisfies(exception -> {
                    ApiException apiException = (ApiException) exception;
                    org.assertj.core.api.Assertions.assertThat(apiException.details())
                            .containsExactly(
                                    new com.example.dailyreport.common.ApiExceptionHandler.ErrorDetail(
                                            "dateFrom", "検索開始日を指定してください。"),
                                    new com.example.dailyreport.common.ApiExceptionHandler.ErrorDetail(
                                            "dateTo", "検索終了日を指定してください。"));
                });
    }

    @Test
    void rejectsDateOrder() {
        assertThatThrownBy(() -> DailyReportDateRangeValidator.validate(
                LocalDate.of(2026, 6, 2), LocalDate.of(2026, 6, 1)))
                .isInstanceOf(ApiException.class)
                .hasMessage("入力内容に誤りがあります。");
    }

    @Test
    void rejectsDateRangeOverLimit() {
        assertThatThrownBy(() -> DailyReportDateRangeValidator.validate(
                LocalDate.of(2025, 1, 1), LocalDate.of(2026, 1, 3)))
                .isInstanceOf(ApiException.class)
                .hasMessage("入力内容に誤りがあります。");
    }
}

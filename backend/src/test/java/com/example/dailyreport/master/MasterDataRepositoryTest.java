package com.example.dailyreport.master;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.example.dailyreport.common.ApiException;
import com.example.dailyreport.common.ApiExceptionHandler;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;

class MasterDataRepositoryTest {
    @Test
    void requireHolidayTypeRejectsMissingHolidayTypeMaster() {
        JdbcTemplate jdbcTemplate = mock(JdbcTemplate.class);
        when(jdbcTemplate.query(anyString(),
                rowMapper(),
                eq("UNKNOWN"))).thenReturn(List.of());
        MasterDataRepository repository = new MasterDataRepository(jdbcTemplate);

        ApiException exception = captureApiException(() -> repository.requireHolidayType("UNKNOWN"));

        assertThat(exception.code()).isEqualTo("VALIDATION_ERROR");
        assertThat(exception.details()).containsExactly(
                new ApiExceptionHandler.ErrorDetail("holidayType", "休日区分が存在しません。"));
    }

    @Test
    void requireWorkSettingsRejectsMissingBreakTypeMaster() {
        JdbcTemplate jdbcTemplate = mock(JdbcTemplate.class);
        when(jdbcTemplate.query(anyString(),
                rowMapper(),
                eq("BT404"))).thenReturn(List.of());
        MasterDataRepository repository = new MasterDataRepository(jdbcTemplate);

        ApiException exception = captureApiException(() -> repository.requireWorkSettings("BT404", "WT001"));

        assertThat(exception.code()).isEqualTo("VALIDATION_ERROR");
        assertThat(exception.details()).containsExactly(
                new ApiExceptionHandler.ErrorDetail("breakTypeId", "休憩区分が存在しません。"));
    }

    @Test
    void requireWorkSettingsRejectsMissingWorkTimeTypeMaster() {
        JdbcTemplate jdbcTemplate = mock(JdbcTemplate.class);
        when(jdbcTemplate.query(anyString(),
                rowMapper(),
                eq("BT001")))
                .thenReturn(List.of(new MasterDataRepository.BreakTypeOption("BT001", "標準休憩")));
        when(jdbcTemplate.query(anyString(),
                rowMapper(),
                eq("WT404"))).thenReturn(List.of());
        MasterDataRepository repository = new MasterDataRepository(jdbcTemplate);

        ApiException exception = captureApiException(() -> repository.requireWorkSettings("BT001", "WT404"));

        assertThat(exception.code()).isEqualTo("VALIDATION_ERROR");
        assertThat(exception.details()).containsExactly(
                new ApiExceptionHandler.ErrorDetail("workTimeTypeId", "勤務区分が存在しません。"));
    }

    @Test
    void projectNameFallsBackToProjectIdWhenMasterIsMissing() {
        JdbcTemplate jdbcTemplate = mock(JdbcTemplate.class);
        when(jdbcTemplate.query(anyString(), rowMapper())).thenReturn(List.of());
        MasterDataRepository repository = new MasterDataRepository(jdbcTemplate);

        assertThat(repository.projectName("P404")).isEqualTo("P404");
    }

    @Test
    void workCategoryNameFallsBackToCategoryIdWhenMasterIsMissing() {
        JdbcTemplate jdbcTemplate = mock(JdbcTemplate.class);
        when(jdbcTemplate.query(anyString(), rowMapper())).thenReturn(List.of());
        MasterDataRepository repository = new MasterDataRepository(jdbcTemplate);

        assertThat(repository.workCategoryName("WC404")).isEqualTo("WC404");
    }

    @Test
    void timePeriodContainsHandlesSameDayAndCrossMidnight() {
        MasterDataRepository.TimePeriod daytime = new MasterDataRepository.TimePeriod(540, 1080);
        MasterDataRepository.TimePeriod overnight = new MasterDataRepository.TimePeriod(1320, 300);

        assertThat(daytime.contains(540)).isTrue();
        assertThat(daytime.contains(1080)).isFalse();
        assertThat(overnight.contains(1320)).isTrue();
        assertThat(overnight.contains(120)).isTrue();
        assertThat(overnight.contains(720)).isFalse();
    }

    @Test
    void timePeriodOverlapMinutesReturnsOnlyOverlapForSameDayRange() {
        MasterDataRepository.TimePeriod lunchBreak = new MasterDataRepository.TimePeriod(720, 780);

        assertThat(lunchBreak.overlapMinutes(660, 810)).isEqualTo(60);
        assertThat(lunchBreak.overlapMinutes(780, 840)).isZero();
    }

    @SuppressWarnings("unchecked")
    private <T> RowMapper<T> rowMapper() {
        return any(RowMapper.class);
    }

    private ApiException captureApiException(ThrowingOperation operation) {
        try {
            operation.run();
        } catch (ApiException exception) {
            return exception;
        }
        throw new AssertionError("Expected ApiException to be thrown.");
    }

    @FunctionalInterface
    private interface ThrowingOperation {
        void run();
    }
}

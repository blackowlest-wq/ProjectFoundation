package com.example.dailyreport.monthlysummary;

import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import com.example.dailyreport.auth.AppUser;
import com.example.dailyreport.auth.AuthenticatedUser;
import com.example.dailyreport.auth.Role;
import com.example.dailyreport.common.ApiException;
import java.time.LocalDate;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;

class MonthlySummaryServiceTest {
    @Test
    void RT_F011_BE_012_rejectsEmployeeAndManagerBeforeParsingYearMonthAndBeforeRepositoryAccess() {
        MonthlySummaryRepository repository = mock(MonthlySummaryRepository.class);
        MonthlySummaryService service = new MonthlySummaryService(repository);

        for (Role role : new Role[]{Role.EMPLOYEE, Role.MANAGER}) {
            assertThatThrownBy(() -> service.get("not-a-year-month", authenticatedUser(role)))
                    .isInstanceOf(ApiException.class)
                    .satisfies(exception -> {
                        ApiException apiException = (ApiException) exception;
                        org.assertj.core.api.Assertions.assertThat(apiException.status().value()).isEqualTo(403);
                        org.assertj.core.api.Assertions.assertThat(apiException.code()).isEqualTo("FORBIDDEN");
                    });
        }
        verifyNoInteractions(repository);
    }

    @Test
    void RT_F011_BE_007_rejectsYearMonthOutsideExactFourDigitTwoDigitContract() {
        MonthlySummaryRepository repository = mock(MonthlySummaryRepository.class);
        MonthlySummaryService service = new MonthlySummaryService(repository);
        AuthenticatedUser admin = authenticatedUser(Role.ADMIN);

        for (String invalid : new String[]{null, "", "2026-6", "20260-06", "+10000-01", "2026-06-01", " 2026-06", "2026-13"}) {
            assertThatThrownBy(() -> service.get(invalid, admin))
                    .isInstanceOf(ApiException.class)
                    .satisfies(exception -> {
                        ApiException apiException = (ApiException) exception;
                        org.assertj.core.api.Assertions.assertThat(apiException.status().value()).isEqualTo(400);
                        org.assertj.core.api.Assertions.assertThat(apiException.code()).isEqualTo("VALIDATION_ERROR");
                        org.assertj.core.api.Assertions.assertThat(apiException.details()).hasSize(1);
                        org.assertj.core.api.Assertions.assertThat(apiException.details().get(0).field()).isEqualTo("yearMonth");
                    });
        }
        verifyNoInteractions(repository);
    }

    @ParameterizedTest
    @CsvSource({
            "2026-01,2026-01-01,2026-02-01",
            "2026-12,2026-12-01,2027-01-01",
            "2028-02,2028-02-01,2028-03-01"
    })
    void RT_F011_BE_006_computesCalendarMonthAsHalfOpenRange(String yearMonth, LocalDate from, LocalDate to) {
        MonthlySummaryRepository repository = mock(MonthlySummaryRepository.class);

        new MonthlySummaryService(repository).get(yearMonth, authenticatedUser(Role.ADMIN));

        verify(repository).employeeWorkSummaries(from, to);
        verify(repository).projectWorkSummaries(from, to);
        verify(repository).categoryWorkSummaries(from, to);
        verify(repository).holidayTypeSummaries(from, to);
    }

    @Test
    void RT_F011_BE_001_returnsFourAggregatesForAdminUsingHalfOpenMonthRange() {
        MonthlySummaryRepository repository = mock(MonthlySummaryRepository.class);
        when(repository.employeeWorkSummaries(LocalDate.of(2026, 6, 1), LocalDate.of(2026, 7, 1)))
                .thenReturn(List.of(new MonthlySummaryResponse.EmployeeWorkSummary("E001", "山田 太郎", 480)));
        when(repository.projectWorkSummaries(LocalDate.of(2026, 6, 1), LocalDate.of(2026, 7, 1)))
                .thenReturn(List.of(new MonthlySummaryResponse.ProjectWorkSummary("P001", "プロジェクトA", 480)));
        when(repository.categoryWorkSummaries(LocalDate.of(2026, 6, 1), LocalDate.of(2026, 7, 1)))
                .thenReturn(List.of(new MonthlySummaryResponse.CategoryWorkSummary("WC001", "設計", 480)));
        when(repository.holidayTypeSummaries(LocalDate.of(2026, 6, 1), LocalDate.of(2026, 7, 1)))
                .thenReturn(List.of(new MonthlySummaryResponse.HolidayTypeSummary("WORKDAY", 1)));

        MonthlySummaryResponse response = new MonthlySummaryService(repository)
                .get("2026-06", authenticatedUser(Role.ADMIN));

        org.assertj.core.api.Assertions.assertThat(response.yearMonth()).isEqualTo("2026-06");
        org.assertj.core.api.Assertions.assertThat(response.employeeWorkSummaries()).containsExactly(
                new MonthlySummaryResponse.EmployeeWorkSummary("E001", "山田 太郎", 480));
        org.assertj.core.api.Assertions.assertThat(response.projectWorkSummaries()).containsExactly(
                new MonthlySummaryResponse.ProjectWorkSummary("P001", "プロジェクトA", 480));
        org.assertj.core.api.Assertions.assertThat(response.categoryWorkSummaries()).containsExactly(
                new MonthlySummaryResponse.CategoryWorkSummary("WC001", "設計", 480));
        org.assertj.core.api.Assertions.assertThat(response.holidayTypeSummaries()).containsExactly(
                new MonthlySummaryResponse.HolidayTypeSummary("WORKDAY", 1));
        verify(repository).employeeWorkSummaries(LocalDate.of(2026, 6, 1), LocalDate.of(2026, 7, 1));
        verify(repository).projectWorkSummaries(LocalDate.of(2026, 6, 1), LocalDate.of(2026, 7, 1));
        verify(repository).categoryWorkSummaries(LocalDate.of(2026, 6, 1), LocalDate.of(2026, 7, 1));
        verify(repository).holidayTypeSummaries(LocalDate.of(2026, 6, 1), LocalDate.of(2026, 7, 1));
    }

    private AuthenticatedUser authenticatedUser(Role role) {
        return new AuthenticatedUser(new AppUser(
                "U-" + role, "E-" + role, role.name().toLowerCase(), "hash", "テスト利用者", role,
                "G001", "第1開発グループ", "BT001", "標準休憩", "WT001", "通常勤務"));
    }
}

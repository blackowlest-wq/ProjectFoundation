/**
 * 管理者向け月次集計の業務Service。
 */
package com.example.dailyreport.monthlysummary;

import com.example.dailyreport.auth.AuthenticatedUser;
import com.example.dailyreport.auth.Role;
import com.example.dailyreport.common.ApiException;
import com.example.dailyreport.common.ApiExceptionHandler.ErrorDetail;
import java.time.DateTimeException;
import java.time.LocalDate;
import java.time.YearMonth;
import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class MonthlySummaryService {
    private static final String YEAR_MONTH_PATTERN = "^[0-9]{4}-[0-9]{2}$";

    private final MonthlySummaryRepository repository;

    public MonthlySummaryService(MonthlySummaryRepository repository) {
        this.repository = repository;
    }

    @Transactional(readOnly = true)
    public MonthlySummaryResponse get(String yearMonth, AuthenticatedUser principal) {
        // How: ADMIN確認を年月解析より先に行い、拒否対象をRepositoryへ到達させない。
        if (principal == null || principal.user().getRole() != Role.ADMIN) {
            throw new ApiException(HttpStatus.FORBIDDEN, "FORBIDDEN", "security.access_denied", "権限がありません。");
        }
        YearMonth target = parseYearMonth(yearMonth);
        LocalDate from = target.atDay(1);
        LocalDate to = target.plusMonths(1).atDay(1);
        return new MonthlySummaryResponse(yearMonth,
                repository.employeeWorkSummaries(from, to),
                repository.projectWorkSummaries(from, to),
                repository.categoryWorkSummaries(from, to),
                repository.holidayTypeSummaries(from, to));
    }

    private YearMonth parseYearMonth(String yearMonth) {
        if (yearMonth == null || !yearMonth.matches(YEAR_MONTH_PATTERN)) {
            throw invalidYearMonth();
        }
        try {
            return YearMonth.parse(yearMonth);
        } catch (DateTimeException exception) {
            throw invalidYearMonth();
        }
    }

    private ApiException invalidYearMonth() {
        return new ApiException(HttpStatus.BAD_REQUEST, "VALIDATION_ERROR", "validation.invalid", "入力内容が不正です。",
                List.of(ErrorDetail.keyed("yearMonth", "validation.invalid_format", "年月はYYYY-MM形式で指定してください。")));
    }
}

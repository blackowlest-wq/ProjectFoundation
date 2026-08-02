/**
 * 日報一覧で共通利用する検索期間の検証を担当する。
 */
package com.example.dailyreport.report;

import com.example.dailyreport.common.ApiException;
import com.example.dailyreport.common.ApiExceptionHandler;
import java.time.LocalDate;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.List;
import org.springframework.http.HttpStatus;

final class DailyReportDateRangeValidator {
    private static final long MAX_SEARCH_DAYS = 366;

    private DailyReportDateRangeValidator() {
    }

    static void validate(LocalDate dateFrom, LocalDate dateTo) {
        List<ApiExceptionHandler.ErrorDetail> details = new ArrayList<>();
        addMissingDateErrors(dateFrom, dateTo, details);
        addDateOrderError(dateFrom, dateTo, details);
        addDateRangeLimitError(dateFrom, dateTo, details);
        throwIfInvalid(details);
    }

    private static void addMissingDateErrors(LocalDate dateFrom, LocalDate dateTo,
                                             List<ApiExceptionHandler.ErrorDetail> details) {
        if (dateFrom == null) {
            details.add(new ApiExceptionHandler.ErrorDetail("dateFrom", "検索開始日を指定してください。"));
        }
        if (dateTo == null) {
            details.add(new ApiExceptionHandler.ErrorDetail("dateTo", "検索終了日を指定してください。"));
        }
    }

    private static void addDateOrderError(LocalDate dateFrom, LocalDate dateTo,
                                          List<ApiExceptionHandler.ErrorDetail> details) {
        if (hasDateRange(dateFrom, dateTo) && dateFrom.isAfter(dateTo)) {
            details.add(new ApiExceptionHandler.ErrorDetail("dateTo", "検索終了日は検索開始日以降にしてください。"));
        }
    }

    private static void addDateRangeLimitError(LocalDate dateFrom, LocalDate dateTo,
                                               List<ApiExceptionHandler.ErrorDetail> details) {
        if (hasDateRange(dateFrom, dateTo) && !dateFrom.isAfter(dateTo)
                && ChronoUnit.DAYS.between(dateFrom, dateTo) > MAX_SEARCH_DAYS) {
            details.add(new ApiExceptionHandler.ErrorDetail("dateTo", "検索対象期間は366日以内で指定してください。"));
        }
    }

    private static boolean hasDateRange(LocalDate dateFrom, LocalDate dateTo) {
        return dateFrom != null && dateTo != null;
    }

    private static void throwIfInvalid(List<ApiExceptionHandler.ErrorDetail> details) {
        if (!details.isEmpty()) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "VALIDATION_ERROR", "入力内容に誤りがあります。", details);
        }
    }
}

/**
 * 保存済み日報を現在のマスタ設定から再検証する。
 */
package com.example.dailyreport.report.logic;

import com.example.dailyreport.common.ApiException;
import com.example.dailyreport.common.ApiExceptionHandler;
import com.example.dailyreport.master.MasterDataRepository;
import com.example.dailyreport.report.entity.DailyReportEntity;
import com.example.dailyreport.report.entity.DailyReportWorkItemEntity;
import java.util.ArrayList;
import java.util.List;
import org.springframework.http.HttpStatus;

final class StoredReportRules {
    private StoredReportRules() {
    }

    static void validate(DailyReportEntity report, MasterDataRepository masterDataRepository) {
        List<ApiExceptionHandler.ErrorDetail> errors = new ArrayList<>();
        if (report.getHolidayType() == null) {
            errors.add(new ApiExceptionHandler.ErrorDetail("holidayType", "休日区分を選択してください。"));
            throw validation(errors);
        }
        MasterDataRepository.HolidayTypeOption holidayType = masterDataRepository.requireHolidayType(report.getHolidayType());
        if (validateNonWorkingDay(report, holidayType, errors)) {
            return;
        }
        validateRequiredInputs(report, errors);
        throwIfInvalid(errors);
        MasterDataRepository.WorkSettings workSettings =
                masterDataRepository.requireWorkSettings(report.getBreakTypeId(), report.getWorkTimeTypeId());
        validateCalculatedValues(report, workSettings, errors);
        throwIfInvalid(errors);
    }

    private static boolean validateNonWorkingDay(DailyReportEntity report,
                                                  MasterDataRepository.HolidayTypeOption holidayType,
                                                  List<ApiExceptionHandler.ErrorDetail> errors) {
        boolean hasWorkItems = !report.getWorkItems().isEmpty();
        boolean hasWorkTimes = report.getStartTimeMinutes() != null || report.getEndTimeMinutes() != null;
        if (holidayType.requiresWorkTime()) {
            return false;
        }
        if (!holidayType.allowsWorkItems()) {
            if (hasWorkTimes || hasWorkItems) {
                errors.add(new ApiExceptionHandler.ErrorDetail("holidayType", "有給休暇では勤務時刻と作業明細を入力できません。"));
            }
            throwIfInvalid(errors);
            return true;
        }
        if (hasWorkItems) {
            return false;
        }
        if (hasWorkTimes) {
            errors.add(new ApiExceptionHandler.ErrorDetail("startTime", "休日で作業明細がない場合、勤務時刻は入力できません。"));
        }
        throwIfInvalid(errors);
        return true;
    }

    private static void validateRequiredInputs(DailyReportEntity report,
                                               List<ApiExceptionHandler.ErrorDetail> errors) {
        if (report.getStartTimeMinutes() == null || report.getEndTimeMinutes() == null) {
            errors.add(new ApiExceptionHandler.ErrorDetail("startTime", "勤務時刻を入力してください。"));
        }
        if (report.getWorkItems().isEmpty()) {
            errors.add(new ApiExceptionHandler.ErrorDetail("workItems", "作業明細を1件以上入力してください。"));
        }
        if (report.getBreakTypeId() == null || report.getWorkTimeTypeId() == null) {
            errors.add(new ApiExceptionHandler.ErrorDetail("workTimeTypeId", "利用者の勤務設定が未設定です。"));
        }
    }

    private static void validateCalculatedValues(DailyReportEntity report,
                                                 MasterDataRepository.WorkSettings workSettings,
                                                 List<ApiExceptionHandler.ErrorDetail> errors) {
        int start = report.getStartTimeMinutes();
        int end = report.getEndTimeMinutes();
        int expectedBreakMinutes = breakMinutes(workSettings, start, end);
        int expectedWorkMinutes = end - start - expectedBreakMinutes;
        validateCalculatedDuration(report, start, end, expectedBreakMinutes, expectedWorkMinutes, errors);
        validateStoredWorkItemTotal(report, expectedWorkMinutes, errors);
        validateStoredBreakdown(report, workSettings, start, end, errors);
    }

    private static void validateCalculatedDuration(DailyReportEntity report, int start, int end,
                                                   int expectedBreakMinutes, int expectedWorkMinutes,
                                                   List<ApiExceptionHandler.ErrorDetail> errors) {
        if (end <= start) {
            errors.add(new ApiExceptionHandler.ErrorDetail("endTime", "勤務終了時刻は勤務開始時刻より後にしてください。"));
        }
        if (expectedBreakMinutes >= end - start || expectedWorkMinutes <= 0) {
            errors.add(new ApiExceptionHandler.ErrorDetail("workMinutes", "勤務時間は1分以上になるように入力してください。"));
        }
        if (!Integer.valueOf(expectedBreakMinutes).equals(report.getBreakMinutes())) {
            errors.add(new ApiExceptionHandler.ErrorDetail("breakMinutes", "保存済みの休憩時間が勤務設定と一致しません。"));
        }
        if (!Integer.valueOf(expectedWorkMinutes).equals(report.getWorkMinutes())) {
            errors.add(new ApiExceptionHandler.ErrorDetail("workMinutes", "保存済みの勤務時間が勤務設定と一致しません。"));
        }
    }

    private static void validateStoredWorkItemTotal(DailyReportEntity report, int expectedWorkMinutes,
                                                    List<ApiExceptionHandler.ErrorDetail> errors) {
        int itemTotal = report.getWorkItems().stream().mapToInt(DailyReportWorkItemEntity::getWorkMinutes).sum();
        if (itemTotal != expectedWorkMinutes) {
            errors.add(new ApiExceptionHandler.ErrorDetail("workItems", "作業時間の合計は実勤務時間と一致させてください。"));
        }
    }

    private static void validateStoredBreakdown(DailyReportEntity report,
                                                MasterDataRepository.WorkSettings workSettings,
                                                int start, int end,
                                                List<ApiExceptionHandler.ErrorDetail> errors) {
        int[] split = splitWork(workSettings, start, end);
        if (!Integer.valueOf(split[0]).equals(report.getRegularWorkMinutes())
                || !Integer.valueOf(split[1]).equals(report.getOvertimeWorkMinutes())
                || !Integer.valueOf(split[2]).equals(report.getNightWorkMinutes())) {
            errors.add(new ApiExceptionHandler.ErrorDetail("workMinutes", "保存済みの勤務時間内訳が勤務設定と一致しません。"));
        }
    }

    private static int breakMinutes(MasterDataRepository.WorkSettings workSettings, int start, int end) {
        return workSettings.breaks().stream()
                .mapToInt(period -> period.overlapMinutes(start, end))
                .sum();
    }

    private static int[] splitWork(MasterDataRepository.WorkSettings workSettings, int start, int end) {
        MasterDataRepository.WorkTimeTypeOption workTimeType = workSettings.workTimeType();
        MasterDataRepository.TimePeriod regularTime = new MasterDataRepository.TimePeriod(
                workTimeType.regularStartMinutes(), workTimeType.regularEndMinutes());
        MasterDataRepository.TimePeriod nightTime = new MasterDataRepository.TimePeriod(
                workTimeType.nightStartMinutes(), workTimeType.nightEndMinutes());
        List<MasterDataRepository.TimePeriod> breaks = workSettings.breaks();
        int regular = 0;
        int overtime = 0;
        int night = 0;
        for (int minute = start; minute < end; minute++) {
            if (containsAny(breaks, minute)) {
                continue;
            }
            if (nightTime.contains(minute)) {
                night++;
            } else if (regularTime.contains(minute)) {
                regular++;
            } else {
                overtime++;
            }
        }
        return new int[]{regular, overtime, night};
    }

    private static boolean containsAny(List<MasterDataRepository.TimePeriod> periods, int minute) {
        return periods.stream().anyMatch(period -> period.contains(minute));
    }

    private static void throwIfInvalid(List<ApiExceptionHandler.ErrorDetail> errors) {
        if (!errors.isEmpty()) {
            throw validation(errors);
        }
    }

    private static ApiException validation(List<ApiExceptionHandler.ErrorDetail> errors) {
        return new ApiException(HttpStatus.BAD_REQUEST, "VALIDATION_ERROR", "入力内容が不正です。", errors);
    }
}

/**
 * 日報の勤務時間・休憩時間・作業時間に関する検証と計算をまとめるロジック。
 * Serviceから業務フローを切り離し、時刻計算と休日区分ごとの入力ルールをここに集約する。
 */
package com.example.dailyreport.report.logic;

import com.example.dailyreport.auth.AppUser;
import com.example.dailyreport.common.ApiException;
import com.example.dailyreport.common.ApiExceptionHandler;
import com.example.dailyreport.master.MasterDataRepository;
import com.example.dailyreport.report.entity.DailyReportEntity;
import com.example.dailyreport.report.entity.DailyReportWorkItemEntity;
import com.example.dailyreport.report.dto.DailyReportRequest;
import java.util.ArrayList;
import java.util.List;
import org.springframework.http.HttpStatus;

public final class TimeRules {

    private TimeRules() {
    }

    public record CalculatedWorkTime(
            Integer startTimeMinutes,
            Integer endTimeMinutes,
            Integer breakMinutes,
            Integer workMinutes,
            Integer regularWorkMinutes,
            Integer overtimeWorkMinutes,
            Integer nightWorkMinutes
    ) {
        public boolean hasWorkTime() {
            // Why not: 開始・終了が欠けた状態で勤務設定を保存すると勤務実績のない記録に設定だけが残るため、時刻がそろう場合だけ保存する。
            return startTimeMinutes != null && endTimeMinutes != null;
        }

        static CalculatedWorkTime empty() {
            return new CalculatedWorkTime(null, null, null, null, null, null, null);
        }
    }

    public static CalculatedWorkTime validateAndCalculate(
            DailyReportRequest request,
            AppUser employee,
            MasterDataRepository masterDataRepository) {
        // How: 明細・休日区分・マスタ・時刻形式を先に検証し、区分別入力検証を通過した後に勤務時間を計算する。
        List<ApiExceptionHandler.ErrorDetail> errors = validateItems(request, masterDataRepository);
        if (request.holidayType() == null) {
            errors.add(new ApiExceptionHandler.ErrorDetail("holidayType", "休日区分を選択してください。"));
        }
        if (!errors.isEmpty()) {
            // Why not: マスタ不在のまま休日区分の業務分岐へ進むと誤った計算になるため、後続処理へ進めないエラーを先に返す。
            throw validation(errors);
        }
        MasterDataRepository.HolidayTypeOption holidayType = masterDataRepository.requireHolidayType(request.holidayType());

        Integer start = parseTime("startTime", request.startTime(), errors);
        Integer end = parseTime("endTime", request.endTime(), errors);
        if (!errors.isEmpty()) {
            throw validation(errors);
        }

        return calculateAfterBasicValidation(request, employee, holidayType, masterDataRepository, start, end, errors);
    }

    public static void validateStoredReport(DailyReportEntity report, MasterDataRepository masterDataRepository) {
        // How: 保存値を休日区分別に検証し、勤務実績がある場合は現在の勤務設定から再計算して保存値と照合する。
        List<ApiExceptionHandler.ErrorDetail> errors = new ArrayList<>();
        if (report.getHolidayType() == null) {
            errors.add(new ApiExceptionHandler.ErrorDetail("holidayType", "休日区分を選択してください。"));
            throw validation(errors);
        }
        MasterDataRepository.HolidayTypeOption holidayType = masterDataRepository.requireHolidayType(report.getHolidayType());

        boolean hasWorkItems = !report.getWorkItems().isEmpty();
        boolean hasWorkTimes = report.getStartTimeMinutes() != null || report.getEndTimeMinutes() != null;

        if (!holidayType.requiresWorkTime() && !holidayType.allowsWorkItems()) {
            // Why not: 有給休暇を通常勤務と同じ計算へ通すと勤務入力を要求してしまうため、勤務入力・明細を持たない区分としてここで完結させる。
            if (hasWorkTimes || hasWorkItems) {
                errors.add(new ApiExceptionHandler.ErrorDetail("holidayType", "有給休暇では勤務時刻と作業明細を入力できません。"));
            }
            throwIfInvalid(errors);
            return;
        }

        if (!holidayType.requiresWorkTime() && holidayType.allowsWorkItems() && !hasWorkItems) {
            // Why not: 作業のない休日に時刻だけを許すと勤務時間の根拠がなくなるため、勤務ゼロとして時刻入力を禁止する。
            if (hasWorkTimes) {
                errors.add(new ApiExceptionHandler.ErrorDetail("startTime", "休日で作業明細がない場合、勤務時刻は入力できません。"));
            }
            throwIfInvalid(errors);
            return;
        }

        if (report.getStartTimeMinutes() == null || report.getEndTimeMinutes() == null) {
            errors.add(new ApiExceptionHandler.ErrorDetail("startTime", "勤務時刻を入力してください。"));
        }
        if (!hasWorkItems) {
            errors.add(new ApiExceptionHandler.ErrorDetail("workItems", "作業明細を1件以上入力してください。"));
        }
        if (report.getBreakTypeId() == null || report.getWorkTimeTypeId() == null) {
            errors.add(new ApiExceptionHandler.ErrorDetail("workTimeTypeId", "利用者の勤務設定が未設定です。"));
        }
        throwIfInvalid(errors);
        MasterDataRepository.WorkSettings workSettings =
                masterDataRepository.requireWorkSettings(report.getBreakTypeId(), report.getWorkTimeTypeId());

        // Why not: 保存済みの計算値だけを信頼すると外部更新による不整合を検出できないため、現在のマスタ設定から再計算して照合する。
        int start = report.getStartTimeMinutes();
        int end = report.getEndTimeMinutes();
        if (end <= start) {
            errors.add(new ApiExceptionHandler.ErrorDetail("endTime", "勤務終了時刻は勤務開始時刻より後にしてください。"));
        }
        int expectedBreakMinutes = breakMinutes(workSettings, start, end);
        int expectedWorkMinutes = end - start - expectedBreakMinutes;
        if (expectedBreakMinutes >= end - start || expectedWorkMinutes <= 0) {
            errors.add(new ApiExceptionHandler.ErrorDetail("workMinutes", "勤務時間は1分以上になるように入力してください。"));
        }
        if (!Integer.valueOf(expectedBreakMinutes).equals(report.getBreakMinutes())) {
            errors.add(new ApiExceptionHandler.ErrorDetail("breakMinutes", "保存済みの休憩時間が勤務設定と一致しません。"));
        }
        if (!Integer.valueOf(expectedWorkMinutes).equals(report.getWorkMinutes())) {
            errors.add(new ApiExceptionHandler.ErrorDetail("workMinutes", "保存済みの勤務時間が勤務設定と一致しません。"));
        }
        int itemTotal = report.getWorkItems().stream().mapToInt(DailyReportWorkItemEntity::getWorkMinutes).sum();
        if (itemTotal != expectedWorkMinutes) {
            errors.add(new ApiExceptionHandler.ErrorDetail("workItems", "作業時間の合計は実勤務時間と一致させてください。"));
        }
        int[] split = splitWork(workSettings, start, end);
        if (!Integer.valueOf(split[0]).equals(report.getRegularWorkMinutes())
                || !Integer.valueOf(split[1]).equals(report.getOvertimeWorkMinutes())
                || !Integer.valueOf(split[2]).equals(report.getNightWorkMinutes())) {
            errors.add(new ApiExceptionHandler.ErrorDetail("workMinutes", "保存済みの勤務時間内訳が勤務設定と一致しません。"));
        }
        throwIfInvalid(errors);
    }

    public static String formatTime(Integer minutes) {
        if (minutes == null) {
            return null;
        }
        // Why not: DBに時刻文字列を保存すると日付跨ぎや差分計算が複雑になるため、分で保持しAPIでHH:mmへ戻す。
        return "%02d:%02d".formatted(minutes / 60, minutes % 60);
    }

    public static String formatDuration(Integer minutes) {
        if (minutes == null) {
            return "0:00";
        }
        return "%d:%02d".formatted(minutes / 60, minutes % 60);
    }

    private static CalculatedWorkTime calculateAfterBasicValidation(
            DailyReportRequest request,
            AppUser employee,
            MasterDataRepository.HolidayTypeOption holidayType,
            MasterDataRepository masterDataRepository,
            Integer start,
            Integer end,
            List<ApiExceptionHandler.ErrorDetail> errors) {
        boolean hasTimes = start != null || end != null;
        boolean hasItems = !request.workItems().isEmpty();

        // How: 有給、作業なし休日、勤務日・作業休日の順に分岐し、最後の経路だけ勤務設定を取得して計算する。
        if (!holidayType.requiresWorkTime() && !holidayType.allowsWorkItems()) {
            // Why not: 勤務入力を持たない区分を0分として扱うと勤務実績があるように見えるため、計算結果を空として返す。
            validatePaidLeave(hasTimes, hasItems, errors);
            throwIfInvalid(errors);
            return CalculatedWorkTime.empty();
        }

        if (!holidayType.requiresWorkTime() && holidayType.allowsWorkItems() && !hasItems) {
            // Why not: 休日かつ作業なしに時刻だけを許すと勤務ゼロと矛盾するため、入力エラーとして扱う。
            validateHolidayWithoutWorkItems(hasTimes, errors);
            throwIfInvalid(errors);
            return CalculatedWorkTime.empty();
        }

        validateWorkedDayInputs(request, holidayType, start, end, errors);
        throwIfInvalid(errors);
        validateEmployeeWorkSettings(employee, errors);
        throwIfInvalid(errors);
        MasterDataRepository.WorkSettings workSettings =
                masterDataRepository.requireWorkSettings(employee.getBreakTypeId(), employee.getWorkTimeTypeId());
        return calculateWorkedDay(request, workSettings, start, end, errors);
    }

    private static void validatePaidLeave(boolean hasTimes, boolean hasItems, List<ApiExceptionHandler.ErrorDetail> errors) {
        if (hasTimes) {
            errors.add(new ApiExceptionHandler.ErrorDetail("startTime", "有給休暇では勤務時刻を入力できません。"));
        }
        if (hasItems) {
            errors.add(new ApiExceptionHandler.ErrorDetail("workItems", "有給休暇では作業明細を入力できません。"));
        }
    }

    private static void validateHolidayWithoutWorkItems(boolean hasTimes, List<ApiExceptionHandler.ErrorDetail> errors) {
        if (hasTimes) {
            errors.add(new ApiExceptionHandler.ErrorDetail("startTime", "休日で作業明細がない場合、勤務時刻は入力できません。"));
        }
    }

    private static void validateWorkedDayInputs(
            DailyReportRequest request,
            MasterDataRepository.HolidayTypeOption holidayType,
            Integer start,
            Integer end,
            List<ApiExceptionHandler.ErrorDetail> errors) {
        if (holidayType.requiresWorkTime() || !request.workItems().isEmpty()) {
            // Why not: 勤務時刻と作業明細の片方だけを許すと集計基準が二つになるため、通常勤務・休日作業ありではセットで必須にする。
            if (start == null) {
                errors.add(new ApiExceptionHandler.ErrorDetail("startTime", "勤務開始時刻を入力してください。"));
            }
            if (end == null) {
                errors.add(new ApiExceptionHandler.ErrorDetail("endTime", "勤務終了時刻を入力してください。"));
            }
            if (request.workItems().isEmpty()) {
                errors.add(new ApiExceptionHandler.ErrorDetail("workItems", "作業明細を1件以上入力してください。"));
            }
        }
        if (start != null && end != null && end <= start) {
            errors.add(new ApiExceptionHandler.ErrorDetail("endTime", "勤務終了時刻は勤務開始時刻より後にしてください。"));
        }
    }

    private static void validateEmployeeWorkSettings(AppUser employee, List<ApiExceptionHandler.ErrorDetail> errors) {
        if (employee.getBreakTypeId() == null || employee.getWorkTimeTypeId() == null) {
            errors.add(new ApiExceptionHandler.ErrorDetail("workTimeTypeId", "利用者の勤務設定が未設定です。"));
        }
    }

    private static CalculatedWorkTime calculateWorkedDay(
            DailyReportRequest request,
            MasterDataRepository.WorkSettings workSettings,
            int start,
            int end,
            List<ApiExceptionHandler.ErrorDetail> errors) {
        int breakMinutes = breakMinutes(workSettings, start, end);
        int elapsed = end - start;
        if (breakMinutes >= elapsed) {
            errors.add(new ApiExceptionHandler.ErrorDetail("breakMinutes", "休憩時間は勤務時間未満になるように設定してください。"));
        }
        int workMinutes = elapsed - breakMinutes;
        if (workMinutes <= 0) {
            errors.add(new ApiExceptionHandler.ErrorDetail("workMinutes", "勤務時間は1分以上になるように入力してください。"));
        }
        int itemTotal = request.workItems().stream().mapToInt(DailyReportRequest.WorkItemRequest::workMinutes).sum();
        if (itemTotal != workMinutes) {
            // Why not: 実勤務時間と作業明細合計のどちらかを正とすると集計が二重基準になるため、不一致を拒否する。
            errors.add(new ApiExceptionHandler.ErrorDetail("workItems", "作業時間の合計は実勤務時間と一致させてください。"));
        }
        throwIfInvalid(errors);

        // How: 入力検証後に勤務区分ごとの分数へ分割し、計算済み値を一つのrecordへまとめる。
        int[] split = splitWork(workSettings, start, end);
        return new CalculatedWorkTime(start, end, breakMinutes, workMinutes, split[0], split[1], split[2]);
    }

    private static Integer parseTime(String field, String value, List<ApiExceptionHandler.ErrorDetail> errors) {
        if (value == null || value.isBlank()) {
            return null;
        }
        if (!value.matches("\\d{2}:\\d{2}")) {
            errors.add(new ApiExceptionHandler.ErrorDetail(field, "時刻はHH:mm形式で入力してください。"));
            return null;
        }
        int hour = Integer.parseInt(value.substring(0, 2));
        int minute = Integer.parseInt(value.substring(3, 5));
        if (hour > 23 || minute > 59) {
            errors.add(new ApiExceptionHandler.ErrorDetail(field, "時刻はHH:mm形式で入力してください。"));
            return null;
        }
        return hour * 60 + minute;
    }

    private static List<ApiExceptionHandler.ErrorDetail> validateItems(
            DailyReportRequest request,
            MasterDataRepository masterDataRepository) {
        List<ApiExceptionHandler.ErrorDetail> errors = new ArrayList<>();
        for (int i = 0; i < request.workItems().size(); i++) {
            DailyReportRequest.WorkItemRequest item = request.workItems().get(i);
            // Why not: 明細全体のエラーだけを返すと入力行を特定できないため、field名にindexを付けて返す。
            if (!masterDataRepository.projectExists(item.projectId())) {
                errors.add(new ApiExceptionHandler.ErrorDetail("workItems[%d].projectId".formatted(i), "案件が存在しません。"));
            }
            if (!masterDataRepository.workCategoryExists(item.workCategoryId())) {
                errors.add(new ApiExceptionHandler.ErrorDetail("workItems[%d].workCategoryId".formatted(i), "作業分類が存在しません。"));
            }
            if (item.workMinutes() == null || item.workMinutes() < 1) {
                errors.add(new ApiExceptionHandler.ErrorDetail("workItems[%d].workMinutes".formatted(i), "作業時間は1分以上で入力してください。"));
            }
        }
        return errors;
    }

    private static int breakMinutes(MasterDataRepository.WorkSettings workSettings, int start, int end) {
        // Why not: 休憩帯が一つとは限らないため、勤務時間帯との重なりを休憩帯ごとに合算する。
        return workSettings.breaks().stream()
                .mapToInt(period -> period.overlapMinutes(start, end))
                .sum();
    }

    private static int[] splitWork(MasterDataRepository.WorkSettings workSettings, int start, int end) {
        // How: 1分ずつ休憩を除外し、深夜、通常、残業の優先順位で分類する。
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
            // Why not: 休憩分を勤務区分へ残すと実勤務時間を過大計上するため、通常・残業・深夜から除外する。
            if (containsAny(breaks, minute)) {
                continue;
            }
            // Why not: 深夜帯を通常・残業にも重ねると深夜残業を二重計上するため、深夜時間を優先して分類する。
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

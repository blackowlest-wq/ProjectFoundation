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
            // 勤務開始・終了がそろっている場合だけ、休憩区分や勤務区分のスナップショットを保存する。
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
        List<ApiExceptionHandler.ErrorDetail> errors = validateItems(request, masterDataRepository);
        if (request.holidayType() == null) {
            errors.add(new ApiExceptionHandler.ErrorDetail("holidayType", "休日区分を選択してください。"));
        }
        if (!errors.isEmpty()) {
            // マスタ存在チェックなど、後続の業務分岐に進めないエラーは先に返す。
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
        List<ApiExceptionHandler.ErrorDetail> errors = new ArrayList<>();
        if (report.getHolidayType() == null) {
            errors.add(new ApiExceptionHandler.ErrorDetail("holidayType", "休日区分を選択してください。"));
            throw validation(errors);
        }
        MasterDataRepository.HolidayTypeOption holidayType = masterDataRepository.requireHolidayType(report.getHolidayType());

        boolean hasWorkItems = !report.getWorkItems().isEmpty();
        boolean hasWorkTimes = report.getStartTimeMinutes() != null || report.getEndTimeMinutes() != null;

        if (!holidayType.requiresWorkTime() && !holidayType.allowsWorkItems()) {
            // 有給休暇のように勤務入力も作業明細も持てない区分は、ここで完結させる。
            if (hasWorkTimes || hasWorkItems) {
                errors.add(new ApiExceptionHandler.ErrorDetail("holidayType", "有給休暇では勤務時刻と作業明細を入力できません。"));
            }
            throwIfInvalid(errors);
            return;
        }

        if (!holidayType.requiresWorkTime() && holidayType.allowsWorkItems() && !hasWorkItems) {
            // 休日で作業しない場合は勤務時間ゼロとして扱い、勤務時刻だけの入力を禁止する。
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

        // 保存済み日報の計算値を、現在のマスタ設定から再計算した期待値と照合する。
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
        // DBでは分単位で保持し、APIレスポンスでは画面入力と同じHH:mm形式へ戻す。
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

        if (!holidayType.requiresWorkTime() && !holidayType.allowsWorkItems()) {
            // 有給休暇などは勤務時間を計算せず、空の計算結果として保存する。
            validatePaidLeave(hasTimes, hasItems, errors);
            throwIfInvalid(errors);
            return CalculatedWorkTime.empty();
        }

        if (!holidayType.requiresWorkTime() && holidayType.allowsWorkItems() && !hasItems) {
            // 休日かつ作業なしは勤務時間ゼロ。時刻入力があれば矛盾として扱う。
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
            // 通常勤務、または休日作業ありの場合は、勤務時刻と作業明細をセットで必須にする。
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
            // 実勤務時間と作業明細合計の不一致を許すと、日報の集計値が二重基準になるため拒否する。
            errors.add(new ApiExceptionHandler.ErrorDetail("workItems", "作業時間の合計は実勤務時間と一致させてください。"));
        }
        throwIfInvalid(errors);

        // 入力チェックを通過してから、通常・残業・深夜の内訳を分単位で確定する。
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
            // 明細ごとにfield名へindexを入れ、画面側でどの行のエラーか追えるようにする。
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
        // 複数休憩帯に対応するため、勤務時間帯との重なりを休憩帯ごとに合算する。
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
            // 休憩中の分は、通常・残業・深夜のどの勤務時間にも含めない。
            if (containsAny(breaks, minute)) {
                continue;
            }
            // 深夜時間は通常/残業より優先して分類し、深夜残業の二重計上を避ける。
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

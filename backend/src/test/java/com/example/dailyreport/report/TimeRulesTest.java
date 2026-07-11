package com.example.dailyreport.report;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.example.dailyreport.auth.AppUser;
import com.example.dailyreport.auth.Role;
import com.example.dailyreport.common.ApiException;
import com.example.dailyreport.master.MasterDataRepository;
import com.example.dailyreport.report.dto.DailyReportRequest;
import com.example.dailyreport.report.entity.DailyReportEntity;
import com.example.dailyreport.report.logic.TimeRules;
import java.lang.reflect.Field;
import java.time.LocalDate;
import java.util.List;
import org.junit.jupiter.api.Test;

class TimeRulesTest {
    @Test
    void validateAndCalculateRejectsMissingHolidayTypeAndInvalidWorkItem() {
        DailyReportRequest request = new DailyReportRequest(
                LocalDate.of(2026, 7, 1),
                null,
                "09:00",
                "18:00",
                "invalid",
                List.of(new DailyReportRequest.WorkItemRequest("BAD", "BAD", 0)));

        assertThatThrownBy(() -> TimeRules.validateAndCalculate(request, employee("BT001", "WT001"), masterData()))
                .isInstanceOf(ApiException.class)
                .hasMessageContaining("入力内容が不正です。");
    }

    @Test
    void validateAndCalculateRejectsEmployeeWithoutWorkSettings() {
        DailyReportRequest request = workday(LocalDate.of(2026, 7, 2), "09:00", "18:00", 480);

        assertThatThrownBy(() -> TimeRules.validateAndCalculate(request, employee(null, null), masterData()))
                .isInstanceOf(ApiException.class)
                .hasMessageContaining("入力内容が不正です。");
    }

    @Test
    void validateAndCalculateSplitsShortWorkTypeEveningBreakOvertimeAndNight() {
        DailyReportRequest request = workday(LocalDate.of(2026, 7, 3), "09:00", "23:00", 765);

        TimeRules.CalculatedWorkTime calculated = TimeRules.validateAndCalculate(request, employee("BT002", "WT002"), masterData());

        assertThat(calculated.breakMinutes()).isEqualTo(75);
        assertThat(calculated.workMinutes()).isEqualTo(765);
        assertThat(calculated.regularWorkMinutes()).isEqualTo(450);
        assertThat(calculated.overtimeWorkMinutes()).isEqualTo(255);
        assertThat(calculated.nightWorkMinutes()).isEqualTo(60);
    }

    @Test
    void validateStoredReportRejectsNullHolidayType() throws Exception {
        DailyReportEntity report = reportWithValidWorkday();
        set(report, "holidayType", null);

        assertThatThrownBy(() -> TimeRules.validateStoredReport(report, masterData()))
                .isInstanceOf(ApiException.class)
                .hasMessageContaining("入力内容が不正です。");
    }

    @Test
    void validateStoredReportRejectsPaidLeaveWithWorkInput() throws Exception {
        DailyReportEntity report = reportWithValidWorkday();
        set(report, "holidayType", "PAID_LEAVE");

        assertThatThrownBy(() -> TimeRules.validateStoredReport(report, masterData()))
                .isInstanceOf(ApiException.class)
                .hasMessageContaining("入力内容が不正です。");
    }

    @Test
    void validateStoredReportRejectsHolidayWithoutItemsButWithTimes() throws Exception {
        DailyReportEntity report = reportWithValidWorkday();
        report.getWorkItems().clear();
        set(report, "holidayType", "HOLIDAY");

        assertThatThrownBy(() -> TimeRules.validateStoredReport(report, masterData()))
                .isInstanceOf(ApiException.class)
                .hasMessageContaining("入力内容が不正です。");
    }

    @Test
    void validateStoredReportRejectsMissingTimesItemsAndSettings() throws Exception {
        DailyReportEntity report = reportWithValidWorkday();
        report.getWorkItems().clear();
        set(report, "startTimeMinutes", null);
        set(report, "endTimeMinutes", null);
        set(report, "breakTypeId", null);
        set(report, "workTimeTypeId", null);

        assertThatThrownBy(() -> TimeRules.validateStoredReport(report, masterData()))
                .isInstanceOf(ApiException.class)
                .hasMessageContaining("入力内容が不正です。");
    }

    @Test
    void validateStoredReportRejectsInconsistentStoredMinutes() throws Exception {
        DailyReportEntity report = reportWithValidWorkday();
        set(report, "breakMinutes", 0);
        set(report, "regularWorkMinutes", 1);

        assertThatThrownBy(() -> TimeRules.validateStoredReport(report, masterData()))
                .isInstanceOf(ApiException.class)
                .hasMessageContaining("入力内容が不正です。");
    }

    private DailyReportEntity reportWithValidWorkday() {
        AppUser employee = employee("BT001", "WT001");
        DailyReportRequest request = workday(LocalDate.of(2026, 7, 4), "09:00", "18:00", 480);
        DailyReportEntity report = new DailyReportEntity("R-test");
        report.setEmployeeSnapshot(employee.getUserId(), employee.getEmployeeId(), employee.getUserName(),
                employee.getGroupId(), employee.getGroupName());
        MasterDataRepository masterData = masterData();
        report.applyContent(request, TimeRules.validateAndCalculate(request, employee, masterData), employee.getBreakTypeId(),
                employee.getBreakTypeName(), employee.getWorkTimeTypeId(), employee.getWorkTimeTypeName());
        return report;
    }

    private DailyReportRequest workday(LocalDate reportDate, String startTime, String endTime, int workMinutes) {
        return new DailyReportRequest(
                reportDate,
                "WORKDAY",
                startTime,
                endTime,
                "remarks",
                List.of(new DailyReportRequest.WorkItemRequest("P001", "WC001", workMinutes)));
    }

    private MasterDataRepository masterData() {
        MasterDataRepository masterData = mock(MasterDataRepository.class);
        when(masterData.projectExists("P001")).thenReturn(true);
        when(masterData.workCategoryExists("WC001")).thenReturn(true);
        when(masterData.requireHolidayType("WORKDAY"))
                .thenReturn(new MasterDataRepository.HolidayTypeOption("WORKDAY", "通常勤務", true, true));
        when(masterData.requireHolidayType("HOLIDAY"))
                .thenReturn(new MasterDataRepository.HolidayTypeOption("HOLIDAY", "休日", false, true));
        when(masterData.requireHolidayType("PAID_LEAVE"))
                .thenReturn(new MasterDataRepository.HolidayTypeOption("PAID_LEAVE", "有給休暇", false, false));
        when(masterData.requireWorkSettings("BT001", "WT001")).thenReturn(workSettings(
                "BT001", "Standard break", "WT001", "Regular work", 1080,
                List.of(new MasterDataRepository.TimePeriod(720, 780))));
        when(masterData.requireWorkSettings("BT002", "WT002")).thenReturn(workSettings(
                "BT002", "Split break", "WT002", "Short work", 1050,
                List.of(
                        new MasterDataRepository.TimePeriod(720, 780),
                        new MasterDataRepository.TimePeriod(1050, 1065))));
        return masterData;
    }

    private MasterDataRepository.WorkSettings workSettings(
            String breakTypeId,
            String breakTypeName,
            String workTimeTypeId,
            String workTimeTypeName,
            int regularEndMinutes,
            List<MasterDataRepository.TimePeriod> breaks) {
        return new MasterDataRepository.WorkSettings(
                new MasterDataRepository.BreakTypeOption(breakTypeId, breakTypeName),
                new MasterDataRepository.WorkTimeTypeOption(workTimeTypeId, workTimeTypeName,
                        540, regularEndMinutes, 1320, 300),
                breaks);
    }

    private AppUser employee(String breakTypeId, String workTimeTypeId) {
        return new AppUser("U-test", "E-test", "employeeTest", "passwordHash",
                "テスト利用者", Role.EMPLOYEE, "G001", "テストグループ",
                breakTypeId, breakTypeId == null ? null : "Break",
                workTimeTypeId, workTimeTypeId == null ? null : "Work");
    }

    private void set(Object target, String fieldName, Object value) throws Exception {
        Field field = target.getClass().getDeclaredField(fieldName);
        field.setAccessible(true);
        field.set(target, value);
    }
}

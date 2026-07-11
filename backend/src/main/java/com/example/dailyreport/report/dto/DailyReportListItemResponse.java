/**
 * 日報カレンダー・一覧画面の検索結果1件を表すDTO。
 */
package com.example.dailyreport.report.dto;

import com.example.dailyreport.report.entity.DailyReportEntity;
import com.example.dailyreport.report.entity.DailyReportWorkItemEntity;
import com.example.dailyreport.report.logic.TimeRules;
import com.example.dailyreport.workflow.ApprovalStatus;
import java.time.LocalDate;
import java.time.OffsetDateTime;

public record DailyReportListItemResponse(
        String reportId,
        LocalDate reportDate,
        String employeeId,
        String employeeName,
        String groupId,
        String groupName,
        String holidayType,
        String startTime,
        String endTime,
        String breakTypeId,
        String breakTypeName,
        String workTimeTypeId,
        String workTimeTypeName,
        Integer breakMinutes,
        Integer workMinutes,
        Integer regularWorkMinutes,
        Integer overtimeWorkMinutes,
        Integer nightWorkMinutes,
        String workTimeDisplay,
        String regularWorkTimeDisplay,
        String overtimeWorkTimeDisplay,
        String nightWorkTimeDisplay,
        Integer totalWorkItemMinutes,
        ApprovalStatus approvalStatus,
        OffsetDateTime submittedAt,
        String approverName,
        OffsetDateTime approvedAt,
        boolean rejected
) {
    public static DailyReportListItemResponse from(DailyReportEntity report) {
        return new DailyReportListItemResponse(
                report.getReportId(),
                report.getReportDate(),
                report.getEmployeeId(),
                report.getEmployeeName(),
                report.getGroupId(),
                report.getGroupName(),
                report.getHolidayType(),
                TimeRules.formatTime(report.getStartTimeMinutes()),
                TimeRules.formatTime(report.getEndTimeMinutes()),
                report.getBreakTypeId(),
                report.getBreakTypeName(),
                report.getWorkTimeTypeId(),
                report.getWorkTimeTypeName(),
                report.getBreakMinutes(),
                report.getWorkMinutes(),
                report.getRegularWorkMinutes(),
                report.getOvertimeWorkMinutes(),
                report.getNightWorkMinutes(),
                TimeRules.formatDuration(report.getWorkMinutes()),
                TimeRules.formatDuration(report.getRegularWorkMinutes()),
                TimeRules.formatDuration(report.getOvertimeWorkMinutes()),
                TimeRules.formatDuration(report.getNightWorkMinutes()),
                report.getWorkItems().stream().mapToInt(DailyReportWorkItemEntity::getWorkMinutes).sum(),
                report.getApprovalStatus(),
                report.getSubmittedAt(),
                null,
                null,
                report.getRejectComment() != null);
    }
}

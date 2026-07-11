/**
 * 日報取得APIの詳細レスポンスDTO。
 * Entityの分単位の時刻・作業時間を画面表示しやすい形式に整形し、マスタ名も付与する。
 */
package com.example.dailyreport.report.dto;

import com.example.dailyreport.master.MasterDataRepository;
import com.example.dailyreport.report.entity.DailyReportEntity;
import com.example.dailyreport.report.entity.DailyReportWorkItemEntity;
import com.example.dailyreport.report.logic.TimeRules;
import com.example.dailyreport.workflow.ApprovalStatus;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.Comparator;
import java.util.List;

public record DailyReportResponse(
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
        String remarks,
        ApprovalStatus approvalStatus,
        OffsetDateTime submittedAt,
        String rejectorId,
        String rejectorName,
        OffsetDateTime rejectedAt,
        String rejectComment,
        List<WorkItemResponse> workItems
) {
    public static DailyReportResponse from(DailyReportEntity report, MasterDataRepository masterDataRepository) {
        // 画面で再編集しやすいよう、保存済みEntityを入力フォームに近い構造へ戻す。
        WorkMinuteSummary workMinuteSummary = WorkMinuteSummary.from(report);
        return new DailyReportResponse(
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
                workMinuteSummary.workTimeDisplay(),
                workMinuteSummary.regularWorkTimeDisplay(),
                workMinuteSummary.overtimeWorkTimeDisplay(),
                workMinuteSummary.nightWorkTimeDisplay(),
                workMinuteSummary.totalWorkItemMinutes(),
                report.getRemarks(),
                report.getApprovalStatus(),
                report.getSubmittedAt(),
                report.getRejectorUserId(),
                report.getRejectorName(),
                report.getRejectedAt(),
                report.getRejectComment(),
                workItemResponses(report, masterDataRepository));
    }

    private static List<WorkItemResponse> workItemResponses(DailyReportEntity report, MasterDataRepository masterDataRepository) {
        // 明細は登録時の表示順を保ち、IDだけでなく表示名も付けて返す。
        return report.getWorkItems().stream()
                .sorted(Comparator.comparingInt(DailyReportWorkItemEntity::getDisplayOrder))
                .map(item -> WorkItemResponse.from(item, masterDataRepository))
                .toList();
    }

    private record WorkMinuteSummary(
            String workTimeDisplay,
            String regularWorkTimeDisplay,
            String overtimeWorkTimeDisplay,
            String nightWorkTimeDisplay,
            int totalWorkItemMinutes
    ) {
        static WorkMinuteSummary from(DailyReportEntity report) {
            // ヘッダの計算結果と明細合計を一緒に返し、画面やテストで整合性を確認しやすくする。
            int total = report.getWorkItems().stream().mapToInt(DailyReportWorkItemEntity::getWorkMinutes).sum();
            return new WorkMinuteSummary(
                    TimeRules.formatDuration(report.getWorkMinutes()),
                    TimeRules.formatDuration(report.getRegularWorkMinutes()),
                    TimeRules.formatDuration(report.getOvertimeWorkMinutes()),
                    TimeRules.formatDuration(report.getNightWorkMinutes()),
                    total);
        }
    }

    public record WorkItemResponse(
            String workItemId,
            String projectId,
            String projectName,
            String workCategoryId,
            String workCategoryName,
            int workMinutes
    ) {
        static WorkItemResponse from(DailyReportWorkItemEntity item, MasterDataRepository masterDataRepository) {
            return new WorkItemResponse(item.getWorkItemId(), item.getProjectId(),
                    masterDataRepository.projectName(item.getProjectId()), item.getWorkCategoryId(),
                    masterDataRepository.workCategoryName(item.getWorkCategoryId()), item.getWorkMinutes());
        }
    }
}

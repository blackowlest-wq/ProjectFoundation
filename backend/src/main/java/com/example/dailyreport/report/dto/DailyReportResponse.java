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
        String approverId,
        String approverName,
        OffsetDateTime approvedAt,
        String rejectorId,
        String rejectorName,
        OffsetDateTime rejectedAt,
        String rejectComment,
        List<WorkItemResponse> workItems
) {
    /**
     * 日報Entityを詳細表示・編集用DTOへ変換し、明細の表示名と計算表示を付加する。
     */
    public static DailyReportResponse from(DailyReportEntity report, MasterDataRepository masterDataRepository) {
        // Why not: Entityの内部構造をそのまま返すと画面入力とDB表現が結合するため、編集用の入力構造へ戻す。
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
                report.getApproverUserId(),
                report.getApproverName(),
                report.getApprovedAt(),
                report.getRejectorUserId(),
                report.getRejectorName(),
                report.getRejectedAt(),
                report.getRejectComment(),
                workItemResponses(report, masterDataRepository));
    }

    /**
     * 明細を保存順で並べ、IDに対応する案件名・作業分類名を付けてレスポンス化する。
     */
    private static List<WorkItemResponse> workItemResponses(DailyReportEntity report, MasterDataRepository masterDataRepository) {
        // Why not: IDだけを返すと履歴表示の時点でマスタ参照が必要になり、表示順も失われるため、保存順と表示名を返す。
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
        /**
         * ヘッダの計算結果と明細合計を画面表示用の勤務時間サマリへまとめる。
         */
        static WorkMinuteSummary from(DailyReportEntity report) {
            // Why not: 画面側で再計算するとバックエンドの計算結果と二重基準になるため、ヘッダ結果と明細合計を同じレスポンスで返す。
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
        /**
         * 作業明細Entityを表示用DTOへ変換し、現在取得できるマスタ名を付ける。
         */
        static WorkItemResponse from(DailyReportWorkItemEntity item, MasterDataRepository masterDataRepository) {
            return new WorkItemResponse(item.getWorkItemId(), item.getProjectId(),
                    masterDataRepository.projectName(item.getProjectId()), item.getWorkCategoryId(),
                    masterDataRepository.workCategoryName(item.getWorkCategoryId()), item.getWorkMinutes());
        }
    }
}

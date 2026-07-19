package com.example.dailyreport.report.dto;

import com.example.dailyreport.workflow.ApprovalStatus;
import java.time.OffsetDateTime;

/**
 * 日報承認の結果を返すレスポンス。
 */
public record ApproveResponse(
        String reportId,
        ApprovalStatus approvalStatus,
        String approverId,
        String approverName,
        OffsetDateTime approvedAt
) {
}

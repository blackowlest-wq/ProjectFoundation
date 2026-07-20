package com.example.dailyreport.report.dto;

import com.example.dailyreport.workflow.ApprovalStatus;
import java.time.OffsetDateTime;

/**
 * 日報差戻しの結果を返すレスポンス。
 */
public record RejectResponse(
        String reportId,
        ApprovalStatus approvalStatus,
        String rejectorId,
        String rejectorName,
        OffsetDateTime rejectedAt,
        String rejectComment
) {
}

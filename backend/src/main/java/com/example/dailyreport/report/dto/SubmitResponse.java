/**
 * 日報提出・再提出APIのレスポンスDTO。
 * 状態遷移後の承認状態と提出日時を画面へ返す。
 */
package com.example.dailyreport.report.dto;

import com.example.dailyreport.workflow.ApprovalStatus;
import java.time.OffsetDateTime;

public record SubmitResponse(String reportId, ApprovalStatus approvalStatus, OffsetDateTime submittedAt) {
}

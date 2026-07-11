/**
 * 日報登録・編集後に返す最小レスポンスDTO。
 * 画面が編集URLと状態表示を更新できるよう、日報IDと承認状態だけを返す。
 */
package com.example.dailyreport.report.dto;

import com.example.dailyreport.workflow.ApprovalStatus;

public record DailyReportSummaryResponse(String reportId, ApprovalStatus approvalStatus) {
}

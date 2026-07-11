/**
 * 日報の承認ワークフロー状態。
 * 登録直後の下書き、提出後の承認待ち、差戻し、承認済みを表す。
 */
package com.example.dailyreport.workflow;

public enum ApprovalStatus {
    DRAFT,
    PENDING,
    REJECTED,
    APPROVED
}

package com.example.dailyreport.report.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/**
 * 日報差戻し時に上長が入力する最新コメント。
 */
public record RejectRequest(
        @NotBlank @Size(max = 1000) String rejectComment
) {
    public RejectRequest {
        rejectComment = rejectComment == null ? null : rejectComment.trim();
    }
}

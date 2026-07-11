/**
 * 日報登録・編集APIの入力DTO。
 * 画面から送られる日付、休日区分、勤務時刻、備考、作業明細を受け取り、基本的な必須・桁数検証を行う。
 */
package com.example.dailyreport.report.dto;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import java.time.LocalDate;
import java.util.List;

public record DailyReportRequest(
        @NotNull LocalDate reportDate,
        @NotNull String holidayType,
        String startTime,
        String endTime,
        @Size(max = 1000) String remarks,
        @Valid List<WorkItemRequest> workItems
) {
    public DailyReportRequest {
        // workItemsをnullのまま扱うと業務ルール側が複雑になるため、空リストへ正規化する。
        workItems = workItems == null ? List.of() : List.copyOf(workItems);
    }

    public record WorkItemRequest(
            @NotNull String projectId,
            @NotNull String workCategoryId,
            @NotNull Integer workMinutes
    ) {
    }
}

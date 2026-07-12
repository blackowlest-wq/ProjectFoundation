/**
 * 日報検索・詳細参照API Controller。
 * HTTPリクエストを受け取り、認証済みユーザー情報と一緒に検索系Serviceへ渡す。
 */
package com.example.dailyreport.report.controller;

import com.example.dailyreport.auth.AuthenticatedUser;
import com.example.dailyreport.report.DailyReportSearchService;
import com.example.dailyreport.report.dto.DailyReportListItemResponse;
import com.example.dailyreport.report.dto.DailyReportResponse;
import com.example.dailyreport.workflow.ApprovalStatus;
import java.time.LocalDate;
import java.util.List;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/daily-reports")
public class DailyReportSearchController {
    private final DailyReportSearchService service;

    public DailyReportSearchController(DailyReportSearchService service) {
        this.service = service;
    }

    @GetMapping
    public List<DailyReportListItemResponse> search(
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate dateFrom,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate dateTo,
            @RequestParam(required = false) String groupId,
            @RequestParam(required = false) String employeeId,
            @RequestParam(required = false, name = "status") ApprovalStatus status,
            @RequestParam(required = false) String holidayType,
            @AuthenticationPrincipal AuthenticatedUser principal) {
        return service.search(dateFrom, dateTo, groupId, employeeId, status, holidayType, principal);
    }

    @GetMapping("/{reportId}")
    public DailyReportResponse get(@PathVariable String reportId,
                                   @AuthenticationPrincipal AuthenticatedUser principal) {
        return service.get(reportId, principal);
    }
}

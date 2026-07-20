/**
 * 上長向けの未承認日報一覧API Controller。
 */
package com.example.dailyreport.report.controller;

import com.example.dailyreport.auth.AuthenticatedUser;
import com.example.dailyreport.report.DailyReportPendingApprovalService;
import com.example.dailyreport.report.dto.DailyReportListItemResponse;
import java.time.LocalDate;
import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/daily-reports")
public class DailyReportPendingApprovalController {
    private static final Logger LOGGER = LoggerFactory.getLogger(DailyReportPendingApprovalController.class);

    private final DailyReportPendingApprovalService service;

    public DailyReportPendingApprovalController(DailyReportPendingApprovalService service) {
        this.service = service;
    }

    @GetMapping("/pending-approvals")
    public List<DailyReportListItemResponse> pendingApprovals(
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate dateFrom,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate dateTo,
            @RequestParam(required = false) String groupId,
            @RequestParam(required = false) String employeeId,
            @AuthenticationPrincipal AuthenticatedUser principal) {
        List<DailyReportListItemResponse> responses = service.search(dateFrom, dateTo, groupId, employeeId, principal);
        LOGGER.info("event=daily_report.pending_approvals_listed feature=DAILY_REPORT useCase=PENDING_APPROVALS userId={} resultCount={}",
                principal.user().getUserId(), responses.size());
        return responses;
    }
}

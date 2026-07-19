package com.example.dailyreport.report.controller;

import com.example.dailyreport.auth.AuthenticatedUser;
import com.example.dailyreport.report.DailyReportApprovalService;
import com.example.dailyreport.report.dto.ApproveResponse;
import com.example.dailyreport.report.dto.RejectRequest;
import com.example.dailyreport.report.dto.RejectResponse;
import jakarta.validation.Valid;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * 日報の承認・差戻しAPI Controller。
 */
@RestController
@RequestMapping("/api/daily-reports")
public class DailyReportApprovalController {
    private static final Logger LOGGER = LoggerFactory.getLogger(DailyReportApprovalController.class);
    private final DailyReportApprovalService service;

    public DailyReportApprovalController(DailyReportApprovalService service) {
        this.service = service;
    }

    @PostMapping("/{reportId}/approve")
    public ApproveResponse approve(@PathVariable String reportId,
                                   @AuthenticationPrincipal AuthenticatedUser principal) {
        ApproveResponse response = service.approve(reportId, principal);
        LOGGER.info("event=daily_report.approved feature=DAILY_REPORT useCase=APPROVE reportId={} userId={} status={}",
                response.reportId(), principal.user().getUserId(), response.approvalStatus());
        return response;
    }

    @PostMapping("/{reportId}/reject")
    public RejectResponse reject(@PathVariable String reportId,
                                 @Valid @RequestBody RejectRequest request,
                                 @AuthenticationPrincipal AuthenticatedUser principal) {
        RejectResponse response = service.reject(reportId, request, principal);
        LOGGER.info("event=daily_report.rejected feature=DAILY_REPORT useCase=REJECT reportId={} userId={} status={}",
                response.reportId(), principal.user().getUserId(), response.approvalStatus());
        return response;
    }
}

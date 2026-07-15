/**
 * 日報提出・再提出API Controller。
 * HTTPリクエストを受け取り、認証済みユーザー情報と一緒に提出系Serviceへ渡す。
 */
package com.example.dailyreport.report.controller;

import com.example.dailyreport.auth.AuthenticatedUser;
import com.example.dailyreport.report.DailyReportSubmissionService;
import com.example.dailyreport.report.dto.SubmitResponse;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

@RestController
@RequestMapping("/api/daily-reports")
public class DailyReportSubmissionController {
    private static final Logger LOGGER = LoggerFactory.getLogger(DailyReportSubmissionController.class);
    private final DailyReportSubmissionService service;

    public DailyReportSubmissionController(DailyReportSubmissionService service) {
        this.service = service;
    }

    @PostMapping("/{reportId}/submit")
    /**
     * 下書き日報を提出し、承認待ち状態へ遷移した結果を返す。
     */
    public SubmitResponse submit(@PathVariable String reportId,
                                 @AuthenticationPrincipal AuthenticatedUser principal) {
        SubmitResponse response = service.submit(reportId, principal);
        LOGGER.info("event=daily_report.submitted feature=DAILY_REPORT useCase=SUBMIT reportId={} status={}",
                response.reportId(), response.approvalStatus());
        return response;
    }

    @PostMapping("/{reportId}/resubmit")
    /**
     * 差戻し日報を再提出し、承認待ち状態へ遷移した結果を返す。
     */
    public SubmitResponse resubmit(@PathVariable String reportId,
                                   @AuthenticationPrincipal AuthenticatedUser principal) {
        SubmitResponse response = service.resubmit(reportId, principal);
        LOGGER.info("event=daily_report.submitted feature=DAILY_REPORT useCase=RESUBMIT reportId={} status={}",
                response.reportId(), response.approvalStatus());
        return response;
    }
}

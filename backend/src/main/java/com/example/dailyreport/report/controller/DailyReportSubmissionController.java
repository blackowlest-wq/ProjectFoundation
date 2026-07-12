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

@RestController
@RequestMapping("/api/daily-reports")
public class DailyReportSubmissionController {
    private final DailyReportSubmissionService service;

    public DailyReportSubmissionController(DailyReportSubmissionService service) {
        this.service = service;
    }

    @PostMapping("/{reportId}/submit")
    public SubmitResponse submit(@PathVariable String reportId,
                                 @AuthenticationPrincipal AuthenticatedUser principal) {
        return service.submit(reportId, principal);
    }

    @PostMapping("/{reportId}/resubmit")
    public SubmitResponse resubmit(@PathVariable String reportId,
                                   @AuthenticationPrincipal AuthenticatedUser principal) {
        return service.resubmit(reportId, principal);
    }
}

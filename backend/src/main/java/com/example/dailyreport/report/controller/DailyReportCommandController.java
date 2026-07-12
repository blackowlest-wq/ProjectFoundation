/**
 * 日報登録・更新API Controller。
 * HTTPリクエストを受け取り、認証済みユーザー情報と一緒に登録更新系Serviceへ渡す。
 */
package com.example.dailyreport.report.controller;

import com.example.dailyreport.auth.AuthenticatedUser;
import com.example.dailyreport.report.DailyReportCommandService;
import com.example.dailyreport.report.dto.DailyReportRequest;
import com.example.dailyreport.report.dto.DailyReportSummaryResponse;
import jakarta.validation.Valid;
import java.net.URI;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/daily-reports")
public class DailyReportCommandController {
    private final DailyReportCommandService service;

    public DailyReportCommandController(DailyReportCommandService service) {
        this.service = service;
    }

    @PostMapping
    public ResponseEntity<DailyReportSummaryResponse> create(@Valid @RequestBody DailyReportRequest request,
                                                             @AuthenticationPrincipal AuthenticatedUser principal) {
        DailyReportSummaryResponse response = service.create(request, principal);
        return ResponseEntity.created(URI.create("/api/daily-reports/" + response.reportId())).body(response);
    }

    @PutMapping("/{reportId}")
    public DailyReportSummaryResponse update(@PathVariable String reportId,
                                             @Valid @RequestBody DailyReportRequest request,
                                             @AuthenticationPrincipal AuthenticatedUser principal) {
        return service.update(reportId, request, principal);
    }
}

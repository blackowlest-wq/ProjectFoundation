/**
 * 日報登録・編集画面から呼び出されるAPI Controller。
 * HTTPリクエストを受け取り、認証済みユーザー情報と一緒にDailyReportServiceへ渡す。
 */
package com.example.dailyreport.report.controller;

import com.example.dailyreport.auth.AuthenticatedUser;
import com.example.dailyreport.report.DailyReportService;
import com.example.dailyreport.report.dto.DailyReportListItemResponse;
import com.example.dailyreport.report.dto.DailyReportRequest;
import com.example.dailyreport.report.dto.DailyReportResponse;
import com.example.dailyreport.report.dto.DailyReportSummaryResponse;
import com.example.dailyreport.report.dto.SubmitResponse;
import com.example.dailyreport.workflow.ApprovalStatus;
import jakarta.validation.Valid;
import java.net.URI;
import java.time.LocalDate;
import java.util.List;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class DailyReportController {
    private final DailyReportService service;

    public DailyReportController(DailyReportService service) {
        this.service = service;
    }

    @PostMapping("/api/daily-reports")
    public ResponseEntity<DailyReportSummaryResponse> create(@Valid @RequestBody DailyReportRequest request,
                                                             @AuthenticationPrincipal AuthenticatedUser principal) {
        DailyReportSummaryResponse response = service.create(request, principal);
        return ResponseEntity.created(URI.create("/api/daily-reports/" + response.reportId())).body(response);
    }

    @GetMapping("/api/daily-reports")
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

    @GetMapping("/api/daily-reports/{reportId}")
    public DailyReportResponse get(@PathVariable String reportId,
                                   @AuthenticationPrincipal AuthenticatedUser principal) {
        return service.get(reportId, principal);
    }

    @PutMapping("/api/daily-reports/{reportId}")
    public DailyReportSummaryResponse update(@PathVariable String reportId,
                                             @Valid @RequestBody DailyReportRequest request,
                                             @AuthenticationPrincipal AuthenticatedUser principal) {
        return service.update(reportId, request, principal);
    }

    @PostMapping("/api/daily-reports/{reportId}/submit")
    public SubmitResponse submit(@PathVariable String reportId,
                                 @AuthenticationPrincipal AuthenticatedUser principal) {
        return service.submit(reportId, principal);
    }

    @PostMapping("/api/daily-reports/{reportId}/resubmit")
    public SubmitResponse resubmit(@PathVariable String reportId,
                                   @AuthenticationPrincipal AuthenticatedUser principal) {
        return service.resubmit(reportId, principal);
    }
}

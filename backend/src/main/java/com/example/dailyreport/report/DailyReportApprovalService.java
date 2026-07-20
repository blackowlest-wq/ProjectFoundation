package com.example.dailyreport.report;

import com.example.dailyreport.auth.AppUser;
import com.example.dailyreport.auth.AuthenticatedUser;
import com.example.dailyreport.common.ApiException;
import com.example.dailyreport.report.dto.ApproveResponse;
import com.example.dailyreport.report.dto.RejectRequest;
import com.example.dailyreport.report.dto.RejectResponse;
import com.example.dailyreport.report.entity.DailyReportEntity;
import com.example.dailyreport.report.entity.DailyReportRepository;
import com.example.dailyreport.workflow.ApprovalStatus;
import java.time.OffsetDateTime;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 上長による日報の承認・差戻しを担当するService。
 */
@Service
public class DailyReportApprovalService {
    private final DailyReportRepository repository;
    private final DailyReportAccessPolicy accessPolicy;

    public DailyReportApprovalService(DailyReportRepository repository, DailyReportAccessPolicy accessPolicy) {
        this.repository = repository;
        this.accessPolicy = accessPolicy;
    }

    @Transactional
    public ApproveResponse approve(String reportId, AuthenticatedUser principal) {
        AppUser user = accessPolicy.requireManager(principal);
        DailyReportEntity report = reportForApproval(reportId, user);
        report.approve(user.getUserId(), user.getUserName(), OffsetDateTime.now());
        return new ApproveResponse(report.getReportId(), report.getApprovalStatus(), report.getApproverUserId(),
                report.getApproverName(), report.getApprovedAt());
    }

    @Transactional
    public RejectResponse reject(String reportId, RejectRequest request, AuthenticatedUser principal) {
        AppUser user = accessPolicy.requireManager(principal);
        DailyReportEntity report = reportForApproval(reportId, user);
        String comment = request.rejectComment().trim();
        report.reject(user.getUserId(), user.getUserName(), OffsetDateTime.now(), comment);
        return new RejectResponse(report.getReportId(), report.getApprovalStatus(), report.getRejectorUserId(),
                report.getRejectorName(), report.getRejectedAt(), report.getRejectComment());
    }

    private DailyReportEntity reportForApproval(String reportId, AppUser user) {
        DailyReportEntity report = repository.findById(reportId)
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "NOT_FOUND", "Daily report was not found."));
        if (!accessPolicy.canReadReport(user, report)) {
            throw new ApiException(HttpStatus.FORBIDDEN, "FORBIDDEN", "Access is forbidden.");
        }
        if (report.getApprovalStatus() != ApprovalStatus.PENDING) {
            throw new ApiException(HttpStatus.CONFLICT, "INVALID_STATUS", "Only pending reports can be processed.");
        }
        return report;
    }
}

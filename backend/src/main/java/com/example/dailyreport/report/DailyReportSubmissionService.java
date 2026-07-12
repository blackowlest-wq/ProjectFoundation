/**
 * 日報の提出・再提出を担当するService。
 */
package com.example.dailyreport.report;

import com.example.dailyreport.auth.AppUser;
import com.example.dailyreport.auth.AuthenticatedUser;
import com.example.dailyreport.common.ApiException;
import com.example.dailyreport.master.MasterDataRepository;
import com.example.dailyreport.report.dto.SubmitResponse;
import com.example.dailyreport.report.entity.DailyReportEntity;
import com.example.dailyreport.report.entity.DailyReportRepository;
import com.example.dailyreport.report.logic.TimeRules;
import com.example.dailyreport.workflow.ApprovalStatus;
import java.time.OffsetDateTime;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class DailyReportSubmissionService {
    private final DailyReportRepository repository;
    private final MasterDataRepository masterDataRepository;
    private final DailyReportAccessPolicy accessPolicy;

    public DailyReportSubmissionService(DailyReportRepository repository, MasterDataRepository masterDataRepository,
                                        DailyReportAccessPolicy accessPolicy) {
        this.repository = repository;
        this.masterDataRepository = masterDataRepository;
        this.accessPolicy = accessPolicy;
    }

    @Transactional
    public SubmitResponse submit(String reportId, AuthenticatedUser principal) {
        AppUser user = accessPolicy.requireEmployee(principal);
        DailyReportEntity report = repository.findByReportIdAndEmployeeUserId(reportId, user.getUserId())
                .orElseThrow(() -> new ApiException(HttpStatus.FORBIDDEN, "FORBIDDEN", "Access is forbidden."));
        // 初回提出は下書きだけ許可し、差戻し後は専用の再提出APIに寄せる。
        if (report.getApprovalStatus() != ApprovalStatus.DRAFT) {
            throw new ApiException(HttpStatus.CONFLICT, "INVALID_STATUS", "Only draft reports can be submitted.");
        }
        // 保存済みデータが外部要因で不整合になっていても、提出直前に再検証して防ぐ。
        TimeRules.validateStoredReport(report, masterDataRepository);
        report.submit(OffsetDateTime.now());
        return new SubmitResponse(report.getReportId(), report.getApprovalStatus(), report.getSubmittedAt());
    }

    @Transactional
    public SubmitResponse resubmit(String reportId, AuthenticatedUser principal) {
        AppUser user = accessPolicy.requireEmployee(principal);
        DailyReportEntity report = repository.findByReportIdAndEmployeeUserId(reportId, user.getUserId())
                .orElseThrow(() -> new ApiException(HttpStatus.FORBIDDEN, "FORBIDDEN", "Access is forbidden."));
        // 差戻し以外を再提出できると状態遷移が崩れるため、明示的にREJECTEDへ限定する。
        if (report.getApprovalStatus() != ApprovalStatus.REJECTED) {
            throw new ApiException(HttpStatus.CONFLICT, "INVALID_STATUS", "Only rejected reports can be resubmitted.");
        }
        TimeRules.validateStoredReport(report, masterDataRepository);
        report.submit(OffsetDateTime.now());
        return new SubmitResponse(report.getReportId(), report.getApprovalStatus(), report.getSubmittedAt());
    }
}

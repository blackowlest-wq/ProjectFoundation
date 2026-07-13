/**
 * 日報の登録・更新を担当するService。
 */
package com.example.dailyreport.report;

import com.example.dailyreport.auth.AppUser;
import com.example.dailyreport.auth.AuthenticatedUser;
import com.example.dailyreport.common.ApiException;
import com.example.dailyreport.master.MasterDataRepository;
import com.example.dailyreport.report.dto.DailyReportRequest;
import com.example.dailyreport.report.dto.DailyReportSummaryResponse;
import com.example.dailyreport.report.entity.DailyReportEntity;
import com.example.dailyreport.report.entity.DailyReportRepository;
import com.example.dailyreport.report.logic.TimeRules;
import com.example.dailyreport.workflow.ApprovalStatus;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class DailyReportCommandService {
    private final DailyReportRepository repository;
    private final MasterDataRepository masterDataRepository;
    private final DailyReportAccessPolicy accessPolicy;

    public DailyReportCommandService(DailyReportRepository repository, MasterDataRepository masterDataRepository,
                                     DailyReportAccessPolicy accessPolicy) {
        this.repository = repository;
        this.masterDataRepository = masterDataRepository;
        this.accessPolicy = accessPolicy;
    }

    @Transactional
    public DailyReportSummaryResponse create(DailyReportRequest request, AuthenticatedUser principal) {
        // How: 本人認可、入力・勤務計算、重複確認、利用者スナップショット、Entity適用、保存の順に処理する。
        AppUser user = accessPolicy.requireEmployee(principal);
        // Why not: 未検証の入力をEntityへ保存すると計算済み時間と明細が不整合になるため、登録前に検証と計算を完了する。
        TimeRules.CalculatedWorkTime calculated = TimeRules.validateAndCalculate(request, user, masterDataRepository);
        if (repository.existsByEmployeeUserIdAndReportDate(user.getUserId(), request.reportDate())) {
            throw new ApiException(HttpStatus.CONFLICT, "DUPLICATE_REPORT", "Daily report already exists.");
        }
        DailyReportEntity report = new DailyReportEntity("R-" + UUID.randomUUID());
        // Why not: 利用者マスタを参照し続けると過去の日報表示が現在の所属・氏名へ変わるため、提出時点の値をスナップショットする。
        report.setEmployeeSnapshot(user.getUserId(), user.getEmployeeId(), user.getUserName(), user.getGroupId(), user.getGroupName());
        apply(request, user, report, calculated);
        DailyReportEntity saved = repository.save(report);
        return new DailyReportSummaryResponse(saved.getReportId(), saved.getApprovalStatus());
    }

    @Transactional
    public DailyReportSummaryResponse update(String reportId, DailyReportRequest request, AuthenticatedUser principal) {
        AppUser user = accessPolicy.requireEmployee(principal);
        DailyReportEntity report = repository.findByReportIdAndEmployeeUserId(reportId, user.getUserId())
                .orElseThrow(() -> new ApiException(HttpStatus.FORBIDDEN, "FORBIDDEN", "Access is forbidden."));
        // Why not: 提出済み・承認済みを編集可能にすると承認内容と実データがずれるため、差戻しだけを修正可能にする。
        if (report.getApprovalStatus() != ApprovalStatus.DRAFT && report.getApprovalStatus() != ApprovalStatus.REJECTED) {
            throw new ApiException(HttpStatus.CONFLICT, "INVALID_STATUS", "Daily report cannot be edited in the current status.");
        }
        TimeRules.CalculatedWorkTime calculated = TimeRules.validateAndCalculate(request, user, masterDataRepository);
        if (repository.existsByEmployeeUserIdAndReportDateAndReportIdNot(user.getUserId(), request.reportDate(), reportId)) {
            throw new ApiException(HttpStatus.CONFLICT, "DUPLICATE_REPORT", "Daily report already exists.");
        }
        apply(request, user, report, calculated);
        return new DailyReportSummaryResponse(report.getReportId(), report.getApprovalStatus());
    }

    private void apply(DailyReportRequest request, AppUser user, DailyReportEntity report, TimeRules.CalculatedWorkTime calculated) {
        if (calculated.hasWorkTime()) {
            // Why not: 勤務入力がない日まで勤務設定を保存すると有給・休日の記録に不要な勤務実績が残るため、勤務入力がある日だけ保存する。
            MasterDataRepository.WorkSettings workSettings =
                    masterDataRepository.requireWorkSettings(user.getBreakTypeId(), user.getWorkTimeTypeId());
            report.applyContent(request, calculated,
                    workSettings.breakType().breakTypeId(), workSettings.breakType().breakTypeName(),
                    workSettings.workTimeType().workTimeTypeId(), workSettings.workTimeType().workTimeTypeName());
            return;
        }
        report.applyContent(request, calculated, null, null, null, null);
    }
}

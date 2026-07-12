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
        AppUser user = accessPolicy.requireEmployee(principal);
        // 登録前に入力値と勤務時間を検証し、保存する計算済み時間を確定する。
        TimeRules.CalculatedWorkTime calculated = TimeRules.validateAndCalculate(request, user, masterDataRepository);
        if (repository.existsByEmployeeUserIdAndReportDate(user.getUserId(), request.reportDate())) {
            throw new ApiException(HttpStatus.CONFLICT, "DUPLICATE_REPORT", "Daily report already exists.");
        }
        DailyReportEntity report = new DailyReportEntity("R-" + UUID.randomUUID());
        // 所属や氏名は後から利用者マスタが変わっても、提出時点の表示を保てるよう日報にスナップショットする。
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
        // 提出済み・承認済みは編集不可。差戻しは修正して再提出できる。
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
            // 勤務入力がある日だけ、利用者に設定された休憩区分・勤務区分を日報へ保存する。
            MasterDataRepository.WorkSettings workSettings =
                    masterDataRepository.requireWorkSettings(user.getBreakTypeId(), user.getWorkTimeTypeId());
            report.applyContent(request, calculated,
                    workSettings.breakType().breakTypeId(), workSettings.breakType().breakTypeName(),
                    workSettings.workTimeType().workTimeTypeId(), workSettings.workTimeType().workTimeTypeName());
            return;
        }
        // 有給休暇など勤務入力がない日は、勤務設定スナップショットも持たせない。
        report.applyContent(request, calculated, null, null, null, null);
    }
}

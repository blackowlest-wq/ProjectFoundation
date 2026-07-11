/**
 * 日報登録・編集・提出の業務フローを担当するService。
 * 認可、状態遷移、重複チェックを制御し、時刻計算はTimeRulesへ委譲する。
 */
package com.example.dailyreport.report;

import com.example.dailyreport.auth.AppUser;
import com.example.dailyreport.auth.AuthenticatedUser;
import com.example.dailyreport.auth.ManagerGroupPermissionRepository;
import com.example.dailyreport.auth.Role;
import com.example.dailyreport.common.ApiException;
import com.example.dailyreport.master.MasterDataRepository;
import com.example.dailyreport.report.dto.DailyReportListItemResponse;
import com.example.dailyreport.report.dto.DailyReportRequest;
import com.example.dailyreport.report.dto.DailyReportResponse;
import com.example.dailyreport.report.dto.DailyReportSummaryResponse;
import com.example.dailyreport.report.dto.SubmitResponse;
import com.example.dailyreport.report.entity.DailyReportEntity;
import com.example.dailyreport.report.entity.DailyReportRepository;
import com.example.dailyreport.report.logic.TimeRules;
import com.example.dailyreport.workflow.ApprovalStatus;
import jakarta.persistence.criteria.Predicate;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import org.springframework.http.HttpStatus;
import org.springframework.data.domain.Sort;
import org.springframework.data.jpa.domain.Specification;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class DailyReportService {
    private static final long MAX_SEARCH_DAYS = 366;

    private final DailyReportRepository repository;
    private final MasterDataRepository masterDataRepository;
    private final ManagerGroupPermissionRepository managerGroupPermissionRepository;

    public DailyReportService(DailyReportRepository repository, MasterDataRepository masterDataRepository,
                              ManagerGroupPermissionRepository managerGroupPermissionRepository) {
        this.repository = repository;
        this.masterDataRepository = masterDataRepository;
        this.managerGroupPermissionRepository = managerGroupPermissionRepository;
    }

    @Transactional
    public DailyReportSummaryResponse create(DailyReportRequest request, AuthenticatedUser principal) {
        AppUser user = requireEmployee(principal);
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

    @Transactional(readOnly = true)
    public DailyReportResponse get(String reportId, AuthenticatedUser principal) {
        DailyReportEntity report = repository.findById(reportId)
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "NOT_FOUND", "Daily report was not found."));
        AppUser user = principal.user();
        if (!canReadReportDetail(user, report)) {
            throw new ApiException(HttpStatus.FORBIDDEN, "FORBIDDEN", "Access is forbidden.");
        }
        return DailyReportResponse.from(report, masterDataRepository);
    }

    @Transactional(readOnly = true)
    public List<DailyReportListItemResponse> search(LocalDate dateFrom, LocalDate dateTo, String groupId,
                                                    String employeeId, ApprovalStatus status, String holidayType,
                                                    AuthenticatedUser principal) {
        validateSearchDateRange(dateFrom, dateTo);
        AppUser user = principal.user();
        List<String> permittedGroupIds = permittedGroupIds(user, groupId);
        if (user.getRole() == Role.MANAGER && permittedGroupIds.isEmpty()) {
            return List.of();
        }

        Specification<DailyReportEntity> specification = searchSpecification(
                dateFrom, dateTo, groupId, employeeId, status, holidayType, user, permittedGroupIds);
        return repository.findAll(specification, Sort.by("reportDate").ascending()
                        .and(Sort.by("employeeId").ascending()))
                .stream()
                .map(DailyReportListItemResponse::from)
                .toList();
    }

    @Transactional
    public DailyReportSummaryResponse update(String reportId, DailyReportRequest request, AuthenticatedUser principal) {
        AppUser user = requireEmployee(principal);
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

    @Transactional
    public SubmitResponse submit(String reportId, AuthenticatedUser principal) {
        AppUser user = requireEmployee(principal);
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
        AppUser user = requireEmployee(principal);
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

    private AppUser requireEmployee(AuthenticatedUser principal) {
        // 日報登録・編集・提出は社員本人の操作に限定する。
        if (principal.user().getRole() != Role.EMPLOYEE) {
            throw new ApiException(HttpStatus.FORBIDDEN, "FORBIDDEN", "Only employees can use this operation.");
        }
        return principal.user();
    }

    private void validateSearchDateRange(LocalDate dateFrom, LocalDate dateTo) {
        List<com.example.dailyreport.common.ApiExceptionHandler.ErrorDetail> details = new ArrayList<>();
        if (dateFrom == null) {
            details.add(new com.example.dailyreport.common.ApiExceptionHandler.ErrorDetail("dateFrom", "検索開始日を指定してください。"));
        }
        if (dateTo == null) {
            details.add(new com.example.dailyreport.common.ApiExceptionHandler.ErrorDetail("dateTo", "検索終了日を指定してください。"));
        }
        if (dateFrom != null && dateTo != null && dateFrom.isAfter(dateTo)) {
            details.add(new com.example.dailyreport.common.ApiExceptionHandler.ErrorDetail("dateTo", "検索終了日は検索開始日以降にしてください。"));
        }
        if (dateFrom != null && dateTo != null && !dateFrom.isAfter(dateTo)
                && ChronoUnit.DAYS.between(dateFrom, dateTo) > MAX_SEARCH_DAYS) {
            details.add(new com.example.dailyreport.common.ApiExceptionHandler.ErrorDetail("dateTo", "検索対象期間は366日以内で指定してください。"));
        }
        if (!details.isEmpty()) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "VALIDATION_ERROR", "入力内容に誤りがあります。", details);
        }
    }

    private boolean canReadReportDetail(AppUser user, DailyReportEntity report) {
        if (user.getRole() == Role.EMPLOYEE) {
            return report.getEmployeeUserId().equals(user.getUserId());
        }
        if (user.getRole() == Role.MANAGER) {
            return managerGroupPermissionRepository.permittedGroupIds(user.getUserId()).contains(report.getGroupId());
        }
        return user.getRole() == Role.ADMIN;
    }

    private List<String> permittedGroupIds(AppUser user, String requestedGroupId) {
        if (user.getRole() != Role.MANAGER) {
            return List.of();
        }
        List<String> permitted = managerGroupPermissionRepository.permittedGroupIds(user.getUserId());
        if (requestedGroupId == null || requestedGroupId.isBlank()) {
            return permitted;
        }
        return permitted.contains(requestedGroupId) ? List.of(requestedGroupId) : List.of();
    }

    private Specification<DailyReportEntity> searchSpecification(LocalDate dateFrom, LocalDate dateTo, String groupId,
                                                                 String employeeId, ApprovalStatus status,
                                                                 String holidayType, AppUser user,
                                                                 List<String> permittedGroupIds) {
        return (root, query, criteriaBuilder) -> {
            List<Predicate> predicates = new ArrayList<>();
            predicates.add(criteriaBuilder.between(root.get("reportDate"), dateFrom, dateTo));
            if (user.getRole() == Role.EMPLOYEE) {
                predicates.add(criteriaBuilder.equal(root.get("employeeUserId"), user.getUserId()));
            } else if (user.getRole() == Role.MANAGER) {
                predicates.add(root.get("groupId").in(permittedGroupIds));
            } else if (groupId != null && !groupId.isBlank()) {
                predicates.add(criteriaBuilder.equal(root.get("groupId"), groupId));
            }
            if (employeeId != null && !employeeId.isBlank()) {
                predicates.add(criteriaBuilder.equal(root.get("employeeId"), employeeId));
            }
            if (status != null) {
                predicates.add(criteriaBuilder.equal(root.get("approvalStatus"), status));
            }
            if (holidayType != null && !holidayType.isBlank()) {
                predicates.add(criteriaBuilder.equal(root.get("holidayType"), holidayType));
            }
            return criteriaBuilder.and(predicates.toArray(Predicate[]::new));
        };
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

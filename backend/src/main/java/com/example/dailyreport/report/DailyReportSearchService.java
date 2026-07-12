/**
 * 日報の検索・詳細参照を担当するService。
 */
package com.example.dailyreport.report;

import com.example.dailyreport.auth.AppUser;
import com.example.dailyreport.auth.AuthenticatedUser;
import com.example.dailyreport.common.ApiException;
import com.example.dailyreport.master.MasterDataRepository;
import com.example.dailyreport.report.dto.DailyReportListItemResponse;
import com.example.dailyreport.report.dto.DailyReportResponse;
import com.example.dailyreport.report.entity.DailyReportEntity;
import com.example.dailyreport.report.entity.DailyReportRepository;
import com.example.dailyreport.workflow.ApprovalStatus;
import jakarta.persistence.criteria.Predicate;
import java.time.LocalDate;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.List;
import org.springframework.data.domain.Sort;
import org.springframework.data.jpa.domain.Specification;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class DailyReportSearchService {
    private static final long MAX_SEARCH_DAYS = 366;

    private final DailyReportRepository repository;
    private final MasterDataRepository masterDataRepository;
    private final DailyReportAccessPolicy accessPolicy;

    public DailyReportSearchService(DailyReportRepository repository, MasterDataRepository masterDataRepository,
                                    DailyReportAccessPolicy accessPolicy) {
        this.repository = repository;
        this.masterDataRepository = masterDataRepository;
        this.accessPolicy = accessPolicy;
    }

    @Transactional(readOnly = true)
    public List<DailyReportListItemResponse> search(LocalDate dateFrom, LocalDate dateTo, String groupId,
                                                    String employeeId, ApprovalStatus status, String holidayType,
                                                    AuthenticatedUser principal) {
        validateSearchDateRange(dateFrom, dateTo);
        AppUser user = principal.user();
        List<String> permittedGroupIds = accessPolicy.permittedGroupIds(user, groupId);
        if (user.getRole() == com.example.dailyreport.auth.Role.MANAGER && permittedGroupIds.isEmpty()) {
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

    @Transactional(readOnly = true)
    public DailyReportResponse get(String reportId, AuthenticatedUser principal) {
        DailyReportEntity report = repository.findById(reportId)
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "NOT_FOUND", "Daily report was not found."));
        AppUser user = principal.user();
        if (!accessPolicy.canReadReport(user, report)) {
            throw new ApiException(HttpStatus.FORBIDDEN, "FORBIDDEN", "Access is forbidden.");
        }
        return DailyReportResponse.from(report, masterDataRepository);
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

    private Specification<DailyReportEntity> searchSpecification(LocalDate dateFrom, LocalDate dateTo, String groupId,
                                                                 String employeeId, ApprovalStatus status,
                                                                 String holidayType, AppUser user,
                                                                 List<String> permittedGroupIds) {
        return (root, query, criteriaBuilder) -> {
            List<Predicate> predicates = new ArrayList<>();
            predicates.add(criteriaBuilder.between(root.get("reportDate"), dateFrom, dateTo));
            if (user.getRole() == com.example.dailyreport.auth.Role.EMPLOYEE) {
                predicates.add(criteriaBuilder.equal(root.get("employeeUserId"), user.getUserId()));
            } else if (user.getRole() == com.example.dailyreport.auth.Role.MANAGER) {
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
}

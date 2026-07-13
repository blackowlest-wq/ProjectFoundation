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
    /**
     * 日付範囲と利用者ロール・権限範囲を検索条件へ反映し、一覧DTOへ変換して返す。
     */
    public List<DailyReportListItemResponse> search(LocalDate dateFrom, LocalDate dateTo, String groupId,
                                                    String employeeId, ApprovalStatus status, String holidayType,
                                                    AuthenticatedUser principal) {
        validateSearchDateRange(dateFrom, dateTo);
        AppUser user = principal.user();
        List<String> permittedGroupIds = accessPolicy.permittedGroupIds(user, groupId);
        // How: 許可グループが一つもない上長には検索を実行せず、空の一覧を返す。
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
    /**
     * 指定日報の存在と参照権限を確認し、詳細DTOへ変換して返す。
     */
    public DailyReportResponse get(String reportId, AuthenticatedUser principal) {
        DailyReportEntity report = repository.findById(reportId)
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "NOT_FOUND", "Daily report was not found."));
        AppUser user = principal.user();
        // How: 参照権限がない場合はDTO変換や詳細情報の返却を行わず、403で終了する。
        if (!accessPolicy.canReadReport(user, report)) {
            throw new ApiException(HttpStatus.FORBIDDEN, "FORBIDDEN", "Access is forbidden.");
        }
        return DailyReportResponse.from(report, masterDataRepository);
    }

    /**
     * 検索開始日・終了日・最大366日の期間制限をまとめて検証する。
     */
    private void validateSearchDateRange(LocalDate dateFrom, LocalDate dateTo) {
        List<com.example.dailyreport.common.ApiExceptionHandler.ErrorDetail> details = new ArrayList<>();
        // How: 開始日が未指定の場合は開始日項目のエラーを追加する。
        if (dateFrom == null) {
            details.add(new com.example.dailyreport.common.ApiExceptionHandler.ErrorDetail("dateFrom", "検索開始日を指定してください。"));
        }
        // How: 終了日が未指定の場合は終了日項目のエラーを追加する。
        if (dateTo == null) {
            details.add(new com.example.dailyreport.common.ApiExceptionHandler.ErrorDetail("dateTo", "検索終了日を指定してください。"));
        }
        // How: 両日付が揃い開始日が後の場合だけ、日付順のエラーを追加する。
        if (dateFrom != null && dateTo != null && dateFrom.isAfter(dateTo)) {
            details.add(new com.example.dailyreport.common.ApiExceptionHandler.ErrorDetail("dateTo", "検索終了日は検索開始日以降にしてください。"));
        }
        // How: 日付順が正しい場合だけ期間日数を計算し、366日を超えたときにエラーを追加する。
        if (dateFrom != null && dateTo != null && !dateFrom.isAfter(dateTo)
                && ChronoUnit.DAYS.between(dateFrom, dateTo) > MAX_SEARCH_DAYS) {
            details.add(new com.example.dailyreport.common.ApiExceptionHandler.ErrorDetail("dateTo", "検索対象期間は366日以内で指定してください。"));
        }
        // How: 集約した検索条件エラーがある場合だけAPI例外を送出し、なければ検索条件の組み立てへ進む。
        if (!details.isEmpty()) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "VALIDATION_ERROR", "入力内容に誤りがあります。", details);
        }
    }

    /**
     * 利用者ロールと任意検索条件をJPA SpecificationのAND条件へ組み立てる。
     */
    private Specification<DailyReportEntity> searchSpecification(LocalDate dateFrom, LocalDate dateTo, String groupId,
                                                                 String employeeId, ApprovalStatus status,
                                                                 String holidayType, AppUser user,
                                                                 List<String> permittedGroupIds) {
        return (root, query, criteriaBuilder) -> {
            List<Predicate> predicates = new ArrayList<>();
            predicates.add(criteriaBuilder.between(root.get("reportDate"), dateFrom, dateTo));
            // How: 社員は自分の日報だけを条件へ追加する。
            if (user.getRole() == com.example.dailyreport.auth.Role.EMPLOYEE) {
                predicates.add(criteriaBuilder.equal(root.get("employeeUserId"), user.getUserId()));
            // How: 上長は指定グループではなく、許可済みグループ集合へ条件を絞り込む。
            } else if (user.getRole() == com.example.dailyreport.auth.Role.MANAGER) {
                predicates.add(root.get("groupId").in(permittedGroupIds));
            // How: 管理者などでグループ条件が指定された場合だけ、そのグループ条件を追加する。
            } else if (groupId != null && !groupId.isBlank()) {
                predicates.add(criteriaBuilder.equal(root.get("groupId"), groupId));
            }
            // How: 社員IDが指定された場合だけ、対象社員の条件を追加する。
            if (employeeId != null && !employeeId.isBlank()) {
                predicates.add(criteriaBuilder.equal(root.get("employeeId"), employeeId));
            }
            // How: 承認状態が指定された場合だけ、状態条件を追加する。
            if (status != null) {
                predicates.add(criteriaBuilder.equal(root.get("approvalStatus"), status));
            }
            // How: 休日区分が指定された場合だけ、休日区分条件を追加する。
            if (holidayType != null && !holidayType.isBlank()) {
                predicates.add(criteriaBuilder.equal(root.get("holidayType"), holidayType));
            }
            return criteriaBuilder.and(predicates.toArray(Predicate[]::new));
        };
    }
}

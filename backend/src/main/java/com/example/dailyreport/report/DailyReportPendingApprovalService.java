/**
 * 上長向けの未承認日報一覧を検索するService。
 */
package com.example.dailyreport.report;

import com.example.dailyreport.auth.AppUser;
import com.example.dailyreport.auth.AuthenticatedUser;
import com.example.dailyreport.common.ApiException;
import com.example.dailyreport.report.dto.DailyReportListItemResponse;
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
public class DailyReportPendingApprovalService {
    private static final long MAX_SEARCH_DAYS = 366;

    private final DailyReportRepository repository;
    private final DailyReportAccessPolicy accessPolicy;

    public DailyReportPendingApprovalService(DailyReportRepository repository, DailyReportAccessPolicy accessPolicy) {
        this.repository = repository;
        this.accessPolicy = accessPolicy;
    }

    /**
     * 上長の許可グループに属する承認待ち日報だけを、表示順を固定して返す。
     */
    @Transactional(readOnly = true)
    public List<DailyReportListItemResponse> search(LocalDate dateFrom, LocalDate dateTo, String groupId,
                                                     String employeeId, AuthenticatedUser principal) {
        AppUser user = accessPolicy.requireManager(principal);
        validateSearchDateRange(dateFrom, dateTo);
        List<String> permittedGroupIds = accessPolicy.permittedGroupIds(user, groupId);
        // How: 担当グループがない上長は検索を実行せず、対象なしとして空一覧を返す。
        if (permittedGroupIds.isEmpty()) {
            return List.of();
        }

        return repository.findAll(pendingApprovalSpecification(dateFrom, dateTo, employeeId, permittedGroupIds),
                        Sort.by("reportDate").ascending().and(Sort.by("employeeId").ascending()))
                .stream()
                .map(DailyReportListItemResponse::from)
                .toList();
    }

    /**
     * 既存の日報一覧と同じ必須・日付順・366日上限の検索条件を検証する。
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
     * 日付範囲・担当グループ・承認待ち状態・任意の社員IDをAND条件として組み立てる。
     */
    private Specification<DailyReportEntity> pendingApprovalSpecification(LocalDate dateFrom, LocalDate dateTo,
                                                                           String employeeId,
                                                                           List<String> permittedGroupIds) {
        return (root, query, criteriaBuilder) -> {
            List<Predicate> predicates = new ArrayList<>();
            predicates.add(criteriaBuilder.between(root.get("reportDate"), dateFrom, dateTo));
            predicates.add(root.get("groupId").in(permittedGroupIds));
            predicates.add(criteriaBuilder.equal(root.get("approvalStatus"), ApprovalStatus.PENDING));
            // How: 社員IDが指定された場合だけ、対象社員の条件を追加する。
            if (employeeId != null && !employeeId.isBlank()) {
                predicates.add(criteriaBuilder.equal(root.get("employeeId"), employeeId));
            }
            return criteriaBuilder.and(predicates.toArray(Predicate[]::new));
        };
    }
}

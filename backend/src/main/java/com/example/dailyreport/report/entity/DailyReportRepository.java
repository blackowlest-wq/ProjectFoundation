/**
 * 日報EntityのSpring Data Repository。
 * 社員本人の日報取得と、同一社員・同一日付の重複チェックに使う。
 */
package com.example.dailyreport.report.entity;

import java.time.LocalDate;
import java.util.Optional;
import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.JpaSpecificationExecutor;
import org.springframework.data.repository.query.Param;
import org.springframework.data.jpa.repository.Query;

public interface DailyReportRepository extends JpaRepository<DailyReportEntity, String>, JpaSpecificationExecutor<DailyReportEntity> {
    boolean existsByEmployeeUserIdAndReportDate(String employeeUserId, LocalDate reportDate);
    boolean existsByEmployeeUserIdAndReportDateAndReportIdNot(String employeeUserId, LocalDate reportDate, String reportId);

    /** 状態変更対象を取得し、先行トランザクションの変更が確定するまで後続処理を待機させる。 */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    Optional<DailyReportEntity> findByReportIdAndEmployeeUserId(String reportId, String employeeUserId);

    /** 上長の状態変更対象を取得し、同一日報への承認・差戻しを直列化する。 */
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("select report from DailyReportEntity report where report.reportId = :reportId")
    Optional<DailyReportEntity> findByReportIdForUpdate(@Param("reportId") String reportId);
}

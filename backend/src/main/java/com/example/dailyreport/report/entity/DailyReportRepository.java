/**
 * 日報EntityのSpring Data Repository。
 * 社員本人の日報取得と、同一社員・同一日付の重複チェックに使う。
 */
package com.example.dailyreport.report.entity;

import java.time.LocalDate;
import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.JpaSpecificationExecutor;

public interface DailyReportRepository extends JpaRepository<DailyReportEntity, String>, JpaSpecificationExecutor<DailyReportEntity> {
    boolean existsByEmployeeUserIdAndReportDate(String employeeUserId, LocalDate reportDate);
    boolean existsByEmployeeUserIdAndReportDateAndReportIdNot(String employeeUserId, LocalDate reportDate, String reportId);
    Optional<DailyReportEntity> findByReportIdAndEmployeeUserId(String reportId, String employeeUserId);
}

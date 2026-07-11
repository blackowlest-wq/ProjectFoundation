/**
 * 日報ヘッダに対応するEntity。
 * 利用者スナップショット、勤務時間の計算結果、承認状態、作業明細をまとめて保持する。
 */
package com.example.dailyreport.report.entity;

import com.example.dailyreport.report.logic.TimeRules;
import com.example.dailyreport.workflow.ApprovalStatus;
import com.example.dailyreport.report.dto.DailyReportRequest;
import jakarta.persistence.CascadeType;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.OneToMany;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.List;

@Entity
@Table(name = "daily_reports",
        uniqueConstraints = @UniqueConstraint(name = "uk_daily_reports_employee_date",
                columnNames = {"employee_user_id", "report_date"}))
public class DailyReportEntity {
    @Id
    @Column(name = "report_id", length = 40)
    private String reportId;

    @Column(name = "employee_user_id", nullable = false, length = 20)
    private String employeeUserId;

    @Column(name = "employee_id", nullable = false, length = 20)
    private String employeeId;

    @Column(name = "employee_name", nullable = false, length = 120)
    private String employeeName;

    @Column(name = "group_id", nullable = false, length = 20)
    private String groupId;

    @Column(name = "group_name", nullable = false, length = 120)
    private String groupName;

    @Column(name = "report_date", nullable = false)
    private LocalDate reportDate;

    @Column(name = "holiday_type", nullable = false, length = 20)
    private String holidayType;

    @Column(name = "break_type_id", length = 20)
    private String breakTypeId;

    @Column(name = "break_type_name", length = 120)
    private String breakTypeName;

    @Column(name = "work_time_type_id", length = 20)
    private String workTimeTypeId;

    @Column(name = "work_time_type_name", length = 120)
    private String workTimeTypeName;

    @Column(name = "start_time_minutes")
    private Integer startTimeMinutes;

    @Column(name = "end_time_minutes")
    private Integer endTimeMinutes;

    @Column(name = "break_minutes")
    private Integer breakMinutes;

    @Column(name = "work_minutes")
    private Integer workMinutes;

    @Column(name = "regular_work_minutes")
    private Integer regularWorkMinutes;

    @Column(name = "overtime_work_minutes")
    private Integer overtimeWorkMinutes;

    @Column(name = "night_work_minutes")
    private Integer nightWorkMinutes;

    @Column(name = "remarks", length = 1000)
    private String remarks;

    @Enumerated(EnumType.STRING)
    @Column(name = "approval_status", nullable = false, length = 20)
    private ApprovalStatus approvalStatus = ApprovalStatus.DRAFT;

    @Column(name = "submitted_at")
    private OffsetDateTime submittedAt;

    @Column(name = "rejector_user_id", length = 20)
    private String rejectorUserId;

    @Column(name = "rejector_name", length = 120)
    private String rejectorName;

    @Column(name = "rejected_at")
    private OffsetDateTime rejectedAt;

    @Column(name = "reject_comment", length = 1000)
    private String rejectComment;

    @OneToMany(mappedBy = "report", cascade = CascadeType.ALL, orphanRemoval = true)
    private List<DailyReportWorkItemEntity> workItems = new ArrayList<>();

    protected DailyReportEntity() {
    }

    public DailyReportEntity(String reportId) {
        this.reportId = reportId;
    }

    public String getReportId() { return reportId; }
    public String getEmployeeUserId() { return employeeUserId; }
    public String getEmployeeId() { return employeeId; }
    public String getEmployeeName() { return employeeName; }
    public String getGroupId() { return groupId; }
    public String getGroupName() { return groupName; }
    public LocalDate getReportDate() { return reportDate; }
    public String getHolidayType() { return holidayType; }
    public String getBreakTypeId() { return breakTypeId; }
    public String getBreakTypeName() { return breakTypeName; }
    public String getWorkTimeTypeId() { return workTimeTypeId; }
    public String getWorkTimeTypeName() { return workTimeTypeName; }
    public Integer getStartTimeMinutes() { return startTimeMinutes; }
    public Integer getEndTimeMinutes() { return endTimeMinutes; }
    public Integer getBreakMinutes() { return breakMinutes; }
    public Integer getWorkMinutes() { return workMinutes; }
    public Integer getRegularWorkMinutes() { return regularWorkMinutes; }
    public Integer getOvertimeWorkMinutes() { return overtimeWorkMinutes; }
    public Integer getNightWorkMinutes() { return nightWorkMinutes; }
    public String getRemarks() { return remarks; }
    public ApprovalStatus getApprovalStatus() { return approvalStatus; }
    public OffsetDateTime getSubmittedAt() { return submittedAt; }
    public String getRejectorUserId() { return rejectorUserId; }
    public String getRejectorName() { return rejectorName; }
    public OffsetDateTime getRejectedAt() { return rejectedAt; }
    public String getRejectComment() { return rejectComment; }
    public List<DailyReportWorkItemEntity> getWorkItems() { return workItems; }

    public void setEmployeeSnapshot(String userId, String employeeId, String employeeName, String groupId, String groupName) {
        // 利用者マスタの変更に影響されず、当時の所属・氏名で日報を表示するため保存時点の値を持つ。
        this.employeeUserId = userId;
        this.employeeId = employeeId;
        this.employeeName = employeeName;
        this.groupId = groupId;
        this.groupName = groupName;
    }

    public void applyContent(DailyReportRequest request, TimeRules.CalculatedWorkTime calculated, String breakTypeId,
                             String breakTypeName, String workTimeTypeId, String workTimeTypeName) {
        // 日報本文と計算済み時間を一括で反映し、Service側にEntity内部の更新順序を漏らさない。
        this.reportDate = request.reportDate();
        this.holidayType = request.holidayType();
        this.remarks = request.remarks();
        this.breakTypeId = calculated.hasWorkTime() ? breakTypeId : null;
        this.breakTypeName = calculated.hasWorkTime() ? breakTypeName : null;
        this.workTimeTypeId = calculated.hasWorkTime() ? workTimeTypeId : null;
        this.workTimeTypeName = calculated.hasWorkTime() ? workTimeTypeName : null;
        this.startTimeMinutes = calculated.startTimeMinutes();
        this.endTimeMinutes = calculated.endTimeMinutes();
        this.breakMinutes = calculated.breakMinutes();
        this.workMinutes = calculated.workMinutes();
        this.regularWorkMinutes = calculated.regularWorkMinutes();
        this.overtimeWorkMinutes = calculated.overtimeWorkMinutes();
        this.nightWorkMinutes = calculated.nightWorkMinutes();
        this.workItems.clear();
        int index = 1;
        for (DailyReportRequest.WorkItemRequest item : request.workItems()) {
            // 明細は画面入力を正として全差し替えし、orphanRemovalで不要明細をDBから削除する。
            this.workItems.add(new DailyReportWorkItemEntity(this, item.projectId(), item.workCategoryId(),
                    item.workMinutes(), index++));
        }
    }

    public void submit(OffsetDateTime now) {
        // 提出・再提出はいずれも承認待ちへ遷移し、提出日時を更新する。
        this.approvalStatus = ApprovalStatus.PENDING;
        this.submittedAt = now;
    }
}

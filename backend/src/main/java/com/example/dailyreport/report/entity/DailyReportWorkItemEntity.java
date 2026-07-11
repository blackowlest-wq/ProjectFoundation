/**
 * 日報作業明細に対応するEntity。
 * 案件、作業分類、作業時間、画面上の表示順を保持する。
 */
package com.example.dailyreport.report.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import java.util.UUID;

@Entity
@Table(name = "daily_report_work_items")
public class DailyReportWorkItemEntity {
    @Id
    @Column(name = "work_item_id", length = 40)
    private String workItemId;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "report_id", nullable = false)
    private DailyReportEntity report;

    @Column(name = "project_id", nullable = false, length = 20)
    private String projectId;

    @Column(name = "work_category_id", nullable = false, length = 20)
    private String workCategoryId;

    @Column(name = "work_minutes", nullable = false)
    private int workMinutes;

    @Column(name = "display_order", nullable = false)
    private int displayOrder;

    protected DailyReportWorkItemEntity() {
    }

    DailyReportWorkItemEntity(DailyReportEntity report, String projectId, String workCategoryId, int workMinutes, int displayOrder) {
        this.workItemId = "WI-" + UUID.randomUUID();
        this.report = report;
        this.projectId = projectId;
        this.workCategoryId = workCategoryId;
        this.workMinutes = workMinutes;
        this.displayOrder = displayOrder;
    }

    public String getWorkItemId() { return workItemId; }
    public String getProjectId() { return projectId; }
    public String getWorkCategoryId() { return workCategoryId; }
    public int getWorkMinutes() { return workMinutes; }
    public int getDisplayOrder() { return displayOrder; }
}

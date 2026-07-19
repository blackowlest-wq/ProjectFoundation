/**
 * 日報機能で共有するフロントエンド型定義。
 * API DTOとフォーム入力値の形を揃え、画面・API・テスト間で同じ型を使えるようにする。
 */
export type ApprovalStatus = 'DRAFT' | 'PENDING' | 'REJECTED' | 'APPROVED';
export type HolidayType = 'WORKDAY' | 'HOLIDAY' | 'PAID_LEAVE' | 'AM_OFF' | 'PM_OFF';

export type ProjectOption = {
  projectId: string;
  projectName: string;
};

export type WorkCategoryOption = {
  workCategoryId: string;
  workCategoryName: string;
};

export type HolidayTypeOption = {
  holidayType: HolidayType;
  holidayTypeName: string;
  requiresWorkTime: boolean;
  allowsWorkItems: boolean;
};

export type DailyReportWorkItemInput = {
  projectId: string;
  workCategoryId: string;
  workMinutes: number;
};

export type DailyReportRequest = {
  reportDate: string;
  holidayType: HolidayType;
  startTime: string | null;
  endTime: string | null;
  remarks: string | null;
  workItems: DailyReportWorkItemInput[];
};

export type DailyReportResponse = DailyReportRequest & {
  reportId: string;
  employeeId: string;
  employeeName: string;
  groupId: string;
  groupName: string;
  breakTypeId: string | null;
  breakTypeName: string | null;
  workTimeTypeId: string | null;
  workTimeTypeName: string | null;
  breakMinutes: number | null;
  workMinutes: number | null;
  regularWorkMinutes: number | null;
  overtimeWorkMinutes: number | null;
  nightWorkMinutes: number | null;
  workTimeDisplay: string;
  regularWorkTimeDisplay: string;
  overtimeWorkTimeDisplay: string;
  nightWorkTimeDisplay: string;
  totalWorkItemMinutes: number;
  approvalStatus: ApprovalStatus;
  submittedAt: string | null;
  approverId: string | null;
  approverName: string | null;
  approvedAt: string | null;
  rejectorId: string | null;
  rejectComment: string | null;
  rejectorName: string | null;
  rejectedAt: string | null;
  workItems: Array<DailyReportWorkItemInput & {
    workItemId: string;
    projectName: string;
    workCategoryName: string;
  }>;
};

export type DailyReportSummary = {
  reportId: string;
  approvalStatus: ApprovalStatus;
};

export type ApproveResponse = {
  reportId: string;
  approvalStatus: 'APPROVED';
  approverId: string;
  approverName: string;
  approvedAt: string;
};

export type RejectResponse = {
  reportId: string;
  approvalStatus: 'REJECTED';
  rejectorId: string;
  rejectorName: string;
  rejectedAt: string;
  rejectComment: string;
};

export type DailyReportListItem = Omit<DailyReportResponse, 'remarks' | 'rejectorId' | 'rejectComment' | 'rejectorName' | 'rejectedAt' | 'workItems'> & {
  approverId: string | null;
  approverName: string | null;
  approvedAt: string | null;
  rejected: boolean;
};

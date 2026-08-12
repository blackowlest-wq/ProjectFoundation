/** 月次集計APIと画面表示で共有する型。 */
export type MonthlySummaryResponse = {
  yearMonth: string;
  employeeWorkSummaries: EmployeeWorkSummary[];
  projectWorkSummaries: ProjectWorkSummary[];
  categoryWorkSummaries: CategoryWorkSummary[];
  holidayTypeSummaries: HolidayTypeSummary[];
};

export type EmployeeWorkSummary = {
  employeeId: string;
  employeeName: string;
  totalWorkMinutes: number;
};

export type ProjectWorkSummary = {
  projectId: string;
  projectName: string;
  totalWorkMinutes: number;
};

export type CategoryWorkSummary = {
  workCategoryId: string;
  workCategoryName: string;
  totalWorkMinutes: number;
};

export type HolidayTypeSummary = {
  holidayType: string;
  totalDays: number;
};

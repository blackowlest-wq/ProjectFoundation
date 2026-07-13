/**
 * 日報フォームの利用者補助用バリデーション。
 * バックエンドのTimeRulesを正としつつ、画面上で即時に分かる入力不備を先に返す。
 */
import type { DailyReportRequest } from './types';

const timePattern = /^\d{2}:\d{2}$/;

function parseTime(value: string | null): number | null {
  if (!value) {
    return null;
  }
  if (!timePattern.test(value)) {
    return null;
  }
  const [hour, minute] = value.split(':').map(Number);
  if (hour > 23 || minute > 59) {
    return null;
  }
  // Why not: 文字列の大小比較では日付内の時刻として扱えないため、バックエンドと同じくHH:mmを分へ変換して比較する。
  return hour * 60 + minute;
}

export function totalWorkItemMinutes(request: DailyReportRequest): number {
  return request.workItems.reduce((total, item) => total + Number(item.workMinutes || 0), 0);
}

export function validateDailyReportInput(request: DailyReportRequest): string | null {
  if (!request.reportDate) {
    return '日付を入力してください。';
  }
  if (!request.holidayType) {
    return '休日区分を選択してください。';
  }
  const hasTimes = Boolean(request.startTime || request.endTime);
  const hasItems = request.workItems.length > 0;
  if (request.holidayType === 'PAID_LEAVE') {
    // Why not: 有給休暇を勤務実績として保存すると勤務集計と矛盾するため、時刻と作業明細を同時に受け付けない。
    if (hasTimes || hasItems) {
      return '有給休暇では勤務時刻と作業明細を入力できません。';
    }
    return null;
  }
  if (request.holidayType === 'HOLIDAY' && !hasItems) {
    // Why not: 作業しない休日に時刻だけを許すと勤務時間の根拠がなくなるため、勤務ゼロとして時刻入力を拒否する。
    return hasTimes ? '休日で作業明細がない場合、勤務時刻は入力できません。' : null;
  }
  if (!request.startTime || !request.endTime || !hasItems) {
    return '勤務時刻と1件以上の作業明細を入力してください。';
  }
  const start = parseTime(request.startTime);
  const end = parseTime(request.endTime);
  if (start === null || end === null) {
    return '時刻はHH:mm形式で入力してください。';
  }
  if (end <= start) {
    return '勤務終了時刻は勤務開始時刻より後にしてください。';
  }
  if (request.workItems.some((item) => item.workMinutes < 1)) {
    return '作業時間は1分以上で入力してください。';
  }
  return null;
}

/**
 * 日報フォームの利用者補助用バリデーション。
 * バックエンドのTimeRulesを正としつつ、画面上で即時に分かる入力不備を先に返す。
 */
import type { DailyReportRequest } from './types';

const timePattern = /^\d{2}:\d{2}$/;

/** HH:mm形式の時刻を日付内の分へ変換し、不正値はnullで返す。 */
function parseTime(value: string | null): number | null {
  // How: 未入力は呼び出し側の必須条件検証へ委ね、nullを返してここではエラーにしない。
  if (!value) {
    return null;
  }
  // How: 形式不正は数値変換せずnullを返し、呼び出し側で形式エラーとして表示する。
  if (!timePattern.test(value)) {
    return null;
  }
  const [hour, minute] = value.split(':').map(Number);
  // How: 時刻範囲外は分へ変換せずnullを返し、呼び出し側で形式エラーとして表示する。
  if (hour > 23 || minute > 59) {
    return null;
  }
  // Why not: 文字列の大小比較では日付内の時刻として扱えないため、バックエンドと同じくHH:mmを分へ変換して比較する。
  return hour * 60 + minute;
}

/** 日報入力に含まれる作業明細の合計分数を返す。 */
export function totalWorkItemMinutes(request: DailyReportRequest): number {
  return request.workItems.reduce((total, item) => total + Number(item.workMinutes || 0), 0);
}

/** 休日区分に応じた時刻・作業明細・勤務時間の入力条件を順番に検証する。 */
export function validateDailyReportInput(request: DailyReportRequest): string | null {
  // How: 日付がない場合は休日区分や勤務内容を検証せず、日付エラーを先に返す。
  if (!request.reportDate) {
    return '日付を入力してください。';
  }
  // How: 休日区分がない場合は区分別ルールへ進まず、選択エラーを先に返す。
  if (!request.holidayType) {
    return '休日区分を選択してください。';
  }
  const hasTimes = Boolean(request.startTime || request.endTime);
  const hasItems = request.workItems.length > 0;
  // How: 有給休暇は勤務時刻・明細の有無を確認して、この区分の検証を完了する。
  if (request.holidayType === 'PAID_LEAVE') {
    // Why not: 有給休暇を勤務実績として保存すると勤務集計と矛盾するため、時刻と作業明細を同時に受け付けない。
    // How: 禁止入力が一つでもあれば有給休暇のエラーを返し、通常勤務の検証へ進めない。
    if (hasTimes || hasItems) {
      return '有給休暇では勤務時刻と作業明細を入力できません。';
    }
    return null;
  }
  // How: 作業明細のない休日は時刻入力の有無だけを確認し、勤務日の検証へ進めない。
  if (request.holidayType === 'HOLIDAY' && !hasItems) {
    // Why not: 作業しない休日に時刻だけを許すと勤務時間の根拠がなくなるため、勤務ゼロとして時刻入力を拒否する。
    // How: 時刻が入力されている場合だけエラーを返し、未入力なら休日として正常終了する。
    return hasTimes ? '休日で作業明細がない場合、勤務時刻は入力できません。' : null;
  }
  // How: 通常勤務または作業する休日では、時刻と明細が揃わなければ計算へ進めない。
  if (!request.startTime || !request.endTime || !hasItems) {
    return '勤務時刻と1件以上の作業明細を入力してください。';
  }
  const start = parseTime(request.startTime);
  const end = parseTime(request.endTime);
  // How: 開始・終了のどちらかが不正なら、時刻順や作業時間の検証へ進めず形式エラーを返す。
  if (start === null || end === null) {
    return '時刻はHH:mm形式で入力してください。';
  }
  // How: 時刻が揃った場合だけ開始・終了順を比較し、逆転していればエラーを返す。
  if (end <= start) {
    return '勤務終了時刻は勤務開始時刻より後にしてください。';
  }
  // How: 明細に1分未満の行が一つでもあれば、勤務時間計算へ進めず入力エラーを返す。
  if (request.workItems.some((item) => item.workMinutes < 1)) {
    return '作業時間は1分以上で入力してください。';
  }
  return null;
}

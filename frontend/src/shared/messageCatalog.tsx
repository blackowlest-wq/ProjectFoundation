/**
 * DBメッセージを画面へ配布するContext。
 * DB取得不能時はソース既定値を使い、既存の直接コンポーネントテストも既定値で動作させる。
 */
import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { fetchMessageCatalog } from './messageApi';

export const MESSAGE_CATALOG_TTL_MS = 5 * 60 * 1000;

export const DEFAULT_MESSAGES: Record<string, string> = {
  'status.draft': '下書き',
  'status.draft_editor': '下書き',
  'status.pending': '承認待ち',
  'status.rejected': '差戻し',
  'status.approved': '承認済み',
  'ui.brand': '日報管理',
  'ui.page_title': '日報カレンダー・一覧',
  'ui.role.employee': '社員',
  'ui.role.manager': '上長',
  'ui.role.admin': '管理者',
  'ui.loading': '読み込み中...',
  'ui.searching': '検索中...',
  'ui.logout': 'ログアウト',
  'ui.logout_failed': 'ログアウトに失敗しました。時間をおいて再度お試しください。',
  'ui.login_required': 'ログインが必要です。',
  'ui.login_failed': 'ログインに失敗しました。',
  'ui.catalog_unavailable': 'メッセージ設定を読み込めませんでした。',
  'auth.login_id.required': 'ログインIDは必須です。',
  'auth.login_id.max_length': 'ログインIDは80文字以内で入力してください。',
  'auth.login_id.invalid_format': 'ログインIDは半角英数字で入力してください。',
  'auth.password.required': 'パスワードは必須です。',
  'auth.password.max_length': 'パスワードは100文字以内で入力してください。',
  'auth.password.invalid_format': 'パスワードは半角英数字で入力してください。',
  'error.daily_report_list': '日報一覧の取得に失敗しました。',
  'error.pending_approvals': '未承認一覧の取得に失敗しました。',
  'error.master_load': 'マスタデータの読み込みに失敗しました。',
  'error.daily_report_load': '日報の読み込みに失敗しました。',
  'error.save_failed': '保存に失敗しました。',
  'error.calculation_reload': '保存は完了しましたが、計算結果の再取得に失敗しました。',
  'error.master_not_ready': '案件と作業分類の読み込みが完了していません。',
  'success.saved': '保存しました。',
  'success.saved_and_submitted': '保存して提出しました。',
  'empty.no_reports': '該当する日報はありません。',
  'empty.no_pending_approvals': '承認待ちの日報はありません。',
  'form.read_only_status': 'この状態の日報は編集できません。',
  'validation.date_required': '日付を入力してください。',
  'validation.holiday_type_required': '休日区分を選択してください。',
  'validation.holiday_type_master_required': '休日区分マスタを読み込んでください。',
  'validation.paid_leave_forbidden': '有給休暇では勤務時刻と作業明細を入力できません。',
  'validation.holiday_work_time_forbidden': '休日で作業明細がない場合、勤務時刻は入力できません。',
  'validation.work_inputs_required': '勤務時刻と1件以上の作業明細を入力してください。',
  'validation.time_format': '時刻はHH:mm形式で入力してください。',
  'validation.end_time_after_start': '勤務終了時刻は勤務開始時刻より後にしてください。',
  'validation.work_item_minutes_positive': '作業時間は1分以上で入力してください。',
  'validation.reject_comment_required': '差し戻しコメントを入力してください。',
  'validation.reject_comment_max_length': '差し戻しコメントは1000文字以内で入力してください。',
  'validation.search_period_required': '対象期間を指定してください。',
  'validation.search_period_format': '対象期間の日付形式が正しくありません。',
  'validation.date_to_before_date_from': '検索終了日は検索開始日以降にしてください。',
};

let currentMessages: Record<string, string> = { ...DEFAULT_MESSAGES };

type MessageContextValue = {
  message: (key: string, fallback?: string) => string;
  refresh: (force?: boolean) => Promise<void>;
};

const MessageContext = createContext<MessageContextValue>({
  message: (key, fallback) => resolveMessage(key, fallback),
  refresh: async () => undefined,
});

/** Providerなしの純粋関数でも、Provider取得済みのDB文言を表示へ反映する。 */
export function resolveMessage(key: string, fallback?: string): string {
  return currentMessages[key] ?? fallback ?? key;
}

export function MessageProvider({ children }: { children: ReactNode }) {
  const [messages, setMessages] = useState<Record<string, string>>({ ...DEFAULT_MESSAGES });
  const loadedAtRef = useRef<number | null>(null);

  const refresh = useCallback(async (force = false) => {
    const now = Date.now();
    if (!force && loadedAtRef.current !== null && now - loadedAtRef.current < MESSAGE_CATALOG_TTL_MS) {
      return;
    }
    try {
      const response = await fetchMessageCatalog();
      const nextMessages = { ...DEFAULT_MESSAGES, ...response.messages };
      loadedAtRef.current = Date.now();
      currentMessages = nextMessages;
      setMessages(nextMessages);
    } catch {
      // Why not: カタログ障害で業務画面を停止させず、既定文言または前回取得値で表示を継続する。
      if (loadedAtRef.current === null) {
        currentMessages = DEFAULT_MESSAGES;
        setMessages({ ...DEFAULT_MESSAGES });
      }
    }
  }, []);

  useEffect(() => {
    void refresh(true);
  }, [refresh]);

  const value = useMemo<MessageContextValue>(() => ({
    message: (key, fallback) => messages[key] ?? fallback ?? key,
    refresh,
  }), [messages, refresh]);

  return <MessageContext.Provider value={value}>{children}</MessageContext.Provider>;
}

export function useMessage(key: string, fallback?: string): string {
  return useContext(MessageContext).message(key, fallback);
}

export function useMessageCatalogActions(): Pick<MessageContextValue, 'refresh'> {
  return useContext(MessageContext);
}

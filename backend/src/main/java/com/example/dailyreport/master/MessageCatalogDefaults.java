/**
 * DBへ接続できない場合にも画面とAPIを利用できるソース側の既定文言。
 * DBは上書き値を提供するが、キー、状態、検証ルールの意味はソースで管理する。
 */
package com.example.dailyreport.master;

import java.util.LinkedHashMap;
import java.util.Map;

public final class MessageCatalogDefaults {
    public static final String DEFAULT_LOCALE = "ja-JP";

    private MessageCatalogDefaults() {
    }

    public static Map<String, String> defaults() {
        Map<String, String> messages = new LinkedHashMap<>();
        messages.put("security.authentication_required", "ログインが必要です。");
        messages.put("security.access_denied", "権限がありません。");
        messages.put("status.draft", "下書き");
        messages.put("status.draft_editor", "下書き");
        messages.put("status.pending", "承認待ち");
        messages.put("status.rejected", "差戻し");
        messages.put("status.approved", "承認済み");
        messages.put("ui.brand", "日報管理");
        messages.put("ui.page_title", "日報カレンダー・一覧");
        messages.put("ui.role.employee", "社員");
        messages.put("ui.role.manager", "上長");
        messages.put("ui.role.admin", "管理者");
        messages.put("ui.loading", "読み込み中...");
        messages.put("ui.searching", "検索中...");
        messages.put("ui.logout", "ログアウト");
        messages.put("ui.logout_failed", "ログアウトに失敗しました。時間をおいて再度お試しください。");
        messages.put("ui.login_required", "ログインが必要です。");
        messages.put("ui.login_failed", "ログインに失敗しました。");
        messages.put("ui.catalog_unavailable", "メッセージ設定を読み込めませんでした。");
        messages.put("error.daily_report_list", "日報一覧の取得に失敗しました。");
        messages.put("error.pending_approvals", "未承認一覧の取得に失敗しました。");
        messages.put("error.master_load", "マスタデータの読み込みに失敗しました。");
        messages.put("error.daily_report_load", "日報の読み込みに失敗しました。");
        messages.put("error.save_failed", "保存に失敗しました。");
        messages.put("error.calculation_reload", "保存は完了しましたが、計算結果の再取得に失敗しました。");
        messages.put("error.master_not_ready", "案件と作業分類の読み込みが完了していません。");
        messages.put("success.saved", "保存しました。");
        messages.put("success.saved_and_submitted", "保存して提出しました。");
        messages.put("empty.no_reports", "該当する日報はありません。");
        messages.put("empty.no_pending_approvals", "承認待ちの日報はありません。");
        messages.put("form.read_only_status", "この状態の日報は編集できません。");
        messages.put("auth.invalid_credentials", "ログインIDまたはパスワードが正しくありません。");
        messages.put("auth.login_id.required", "ログインIDは必須です。");
        messages.put("auth.login_id.max_length", "ログインIDは80文字以内で入力してください。");
        messages.put("auth.login_id.invalid_format", "ログインIDは半角英数字で入力してください。");
        messages.put("auth.password.required", "パスワードは必須です。");
        messages.put("auth.password.max_length", "パスワードは100文字以内で入力してください。");
        messages.put("auth.password.invalid_format", "パスワードは半角英数字で入力してください。");
        messages.put("validation.invalid", "入力内容に誤りがあります。");
        messages.put("validation.invalid_format", "形式が正しくありません。");
        messages.put("validation.date_required", "日付を入力してください。");
        messages.put("validation.holiday_type_master_required", "休日区分マスタを読み込んでください。");
        messages.put("validation.paid_leave_forbidden", "有給休暇では勤務時刻と作業明細を入力できません。");
        messages.put("validation.work_inputs_required", "勤務時刻と1件以上の作業明細を入力してください。");
        messages.put("validation.reject_comment_required", "差し戻しコメントを入力してください。");
        messages.put("validation.reject_comment_max_length", "差し戻しコメントは1000文字以内で入力してください。");
        messages.put("validation.search_period_required", "対象期間を指定してください。");
        messages.put("validation.search_period_format", "対象期間の日付形式が正しくありません。");
        messages.put("validation.holiday_type_required", "休日区分を選択してください。");
        messages.put("validation.holiday_type_not_found", "休日区分が存在しません。");
        messages.put("validation.break_type_not_found", "休憩区分が存在しません。");
        messages.put("validation.work_time_type_not_found", "勤務区分が存在しません。");
        messages.put("validation.paid_leave_work_time_forbidden", "有給休暇では勤務時刻を入力できません。");
        messages.put("validation.paid_leave_work_items_forbidden", "有給休暇では作業明細を入力できません。");
        messages.put("validation.holiday_work_time_forbidden", "休日で作業明細がない場合、勤務時刻は入力できません。");
        messages.put("validation.start_time_required", "勤務開始時刻を入力してください。");
        messages.put("validation.end_time_required", "勤務終了時刻を入力してください。");
        messages.put("validation.work_items_required", "作業明細を1件以上入力してください。");
        messages.put("validation.end_time_after_start", "勤務終了時刻は勤務開始時刻より後にしてください。");
        messages.put("validation.work_time_type_required", "社員の勤務設定が未設定です。");
        messages.put("validation.break_minutes_less_than_work", "休憩時間は勤務時間未満になるように設定してください。");
        messages.put("validation.work_minutes_positive", "勤務時間は1分以上になるように入力してください。");
        messages.put("validation.work_items_minutes_match", "作業時間の合計は実勤務時間と一致させてください。");
        messages.put("validation.time_format", "時刻はHH:mm形式で入力してください。");
        messages.put("validation.project_not_found", "案件が存在しません。");
        messages.put("validation.work_category_not_found", "作業分類が存在しません。");
        messages.put("validation.work_item_minutes_positive", "作業時間は1分以上で入力してください。");
        messages.put("validation.date_from_required", "検索開始日を指定してください。");
        messages.put("validation.date_to_required", "検索終了日を指定してください。");
        messages.put("validation.date_to_before_date_from", "検索終了日は検索開始日以降にしてください。");
        messages.put("validation.date_range_too_long", "検索対象期間は366日以内で指定してください。");
        messages.put("validation.stored_paid_leave_invalid", "有給休暇では勤務時刻と作業明細を入力できません。");
        messages.put("validation.stored_work_time_required", "勤務時刻を入力してください。");
        messages.put("validation.stored_break_minutes_mismatch", "保存済みの休憩時間が勤務設定と一致しません。");
        messages.put("validation.stored_work_minutes_mismatch", "保存済みの勤務時間が勤務設定と一致しません。");
        messages.put("validation.stored_work_item_minutes_mismatch", "保存済みの勤務時間内訳が勤務設定と一致しません。");
        messages.put("report.not_found", "Daily report was not found.");
        messages.put("report.forbidden", "Access is forbidden.");
        messages.put("report.duplicate", "Daily report already exists.");
        messages.put("report.invalid_status", "Daily report cannot be edited in the current status.");
        messages.put("report.only_employees", "Only employees can use this operation.");
        messages.put("report.only_managers", "Only managers can use this operation.");
        messages.put("report.submit_draft_only", "Only draft reports can be submitted.");
        messages.put("report.resubmit_rejected_only", "Only rejected reports can be resubmitted.");
        messages.put("report.approve_pending_only", "Only pending reports can be processed.");
        messages.put("business.conflict", "業務処理を完了できません。");
        messages.put("system.unexpected", "システムエラーが発生しました。");
        return Map.copyOf(messages);
    }
}

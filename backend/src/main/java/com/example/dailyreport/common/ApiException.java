/**
 * APIで返す業務エラーをHTTPステータス、エラーコード、詳細付きで表す例外。
 * Controller層ではなく業務処理側から共通レスポンス形式へつなぐために利用する。
 */
package com.example.dailyreport.common;

import java.util.List;
import org.springframework.http.HttpStatus;

public class ApiException extends RuntimeException {
    private final HttpStatus status;
    private final String code;
    private final String messageKey;
    private final List<ApiExceptionHandler.ErrorDetail> details;

    /**
     * 詳細情報を持たないAPI例外を生成する。
     */
    public ApiException(HttpStatus status, String code, String message) {
        this(status, code, message, List.of());
    }

    /**
     * 安定したメッセージキーと、DB利用不能時のフォールバック文言を持つAPI例外を生成する。
     */
    public ApiException(HttpStatus status, String code, String messageKey, String fallbackMessage) {
        this(status, code, messageKey, fallbackMessage, List.of());
    }

    /**
     * HTTPステータス、エラーコード、画面表示文言、項目別詳細を持つAPI例外を生成する。
     */
    public ApiException(HttpStatus status, String code, String message,
                        List<ApiExceptionHandler.ErrorDetail> details) {
        this(status, code, null, message, details);
    }

    /**
     * 安定したメッセージキー、フォールバック文言、項目別詳細を持つAPI例外を生成する。
     */
    public ApiException(HttpStatus status, String code, String messageKey, String fallbackMessage,
                        List<ApiExceptionHandler.ErrorDetail> details) {
        super(fallbackMessage);
        this.status = status;
        this.code = code;
        this.messageKey = messageKey;
        this.details = details;
    }

    /** APIレスポンスへ設定するHTTPステータスを返す。 */
    public HttpStatus status() { return status; }
    /** APIレスポンスへ設定するエラーコードを返す。 */
    public String code() { return code; }
    /** APIレスポンスの表示文言を解決するための安定キーを返す。 */
    public String messageKey() { return messageKey; }
    /** APIレスポンスへ設定する項目別詳細を返す。 */
    public List<ApiExceptionHandler.ErrorDetail> details() { return details; }
}

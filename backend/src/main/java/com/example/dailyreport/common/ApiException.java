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
    private final List<ApiExceptionHandler.ErrorDetail> details;

    public ApiException(HttpStatus status, String code, String message) {
        this(status, code, message, List.of());
    }

    public ApiException(HttpStatus status, String code, String message,
                        List<ApiExceptionHandler.ErrorDetail> details) {
        super(message);
        this.status = status;
        this.code = code;
        this.details = details;
    }

    public HttpStatus status() { return status; }
    public String code() { return code; }
    public List<ApiExceptionHandler.ErrorDetail> details() { return details; }
}

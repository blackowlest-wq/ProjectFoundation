/**
 * アプリケーション例外をフロントエンド向けのJSONエラーレスポンスへ変換する。
 * 入力チェックエラーはfield単位の詳細を保持し、画面で具体的に表示できるようにする。
 */
package com.example.dailyreport.common;

import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException;

@RestControllerAdvice
public class ApiExceptionHandler {
    public record ErrorDetail(String field, String message) {
    }

    public record ErrorResponse(String code, String message, List<ErrorDetail> details) {
    }

    @ExceptionHandler(BadCredentialsException.class)
    /**
     * 認証失敗を、利用者の存在を推測できない共通401レスポンスへ変換する。
     */
    public ResponseEntity<ErrorResponse> badCredentials() {
        return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                .body(new ErrorResponse("AUTHENTICATION_FAILED", "ログインIDまたはパスワードが正しくありません。", List.of()));
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    /**
     * Bean Validationの項目別エラーを、画面が表示できる共通400レスポンスへ変換する。
     */
    public ResponseEntity<ErrorResponse> validation(MethodArgumentNotValidException exception) {
        List<ErrorDetail> details = exception.getBindingResult().getFieldErrors().stream()
                .map(error -> new ErrorDetail(error.getField(), error.getDefaultMessage()))
                .toList();
        return ResponseEntity.badRequest()
                .body(new ErrorResponse("VALIDATION_ERROR", "入力内容に誤りがあります。", details));
    }

    @ExceptionHandler(MethodArgumentTypeMismatchException.class)
    /**
     * URLパラメータ等の型変換失敗を、入力項目名付きの共通400レスポンスへ変換する。
     */
    public ResponseEntity<ErrorResponse> argumentTypeMismatch(MethodArgumentTypeMismatchException exception) {
        String fieldName = exception.getName() != null ? exception.getName() : "request";
        return ResponseEntity.badRequest()
                .body(new ErrorResponse("VALIDATION_ERROR", "入力内容に誤りがあります。",
                        List.of(new ErrorDetail(fieldName, "形式が正しくありません。"))));
    }

    @ExceptionHandler(ApiException.class)
    /**
     * 業務処理が投げたAPI例外を、指定されたステータスと詳細を持つレスポンスへ変換する。
     */
    public ResponseEntity<ErrorResponse> apiException(ApiException exception) {
        return ResponseEntity.status(exception.status())
                .body(new ErrorResponse(exception.code(), exception.getMessage(), exception.details()));
    }
}

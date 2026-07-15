/**
 * アプリケーション例外をフロントエンド向けのJSONエラーレスポンスへ変換する。
 * 入力チェックエラーはfield単位の詳細を保持し、画面で具体的に表示できるようにする。
 */
package com.example.dailyreport.common;

import com.example.dailyreport.observability.ExceptionLog;
import com.example.dailyreport.observability.RequestContext;
import jakarta.servlet.http.HttpServletRequest;
import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.web.bind.MissingPathVariableException;
import org.springframework.web.bind.MissingServletRequestParameterException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

@RestControllerAdvice
public class ApiExceptionHandler {
    private static final Logger LOGGER = LoggerFactory.getLogger(ApiExceptionHandler.class);

    public record ErrorDetail(String field, String message) {
    }

    public record ErrorResponse(String code, String message, List<ErrorDetail> details, String requestId) {
    }

    @ExceptionHandler(BadCredentialsException.class)
    /**
     * 認証失敗を、利用者の存在を推測できない共通401レスポンスへ変換する。
     */
    public ResponseEntity<ErrorResponse> badCredentials(HttpServletRequest request) {
        String requestId = requestId(request);
        LOGGER.warn("event=security.authentication_failed requestId={} feature={} useCase={} status={} code={}",
                requestId, RequestContext.feature(request), RequestContext.useCase(request),
                HttpStatus.UNAUTHORIZED.value(), "AUTHENTICATION_FAILED");
        return errorResponse(HttpStatus.UNAUTHORIZED, "AUTHENTICATION_FAILED",
                "ログインIDまたはパスワードが正しくありません。", List.of(), requestId);
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    /**
     * Bean Validationの項目別エラーを、画面が表示できる共通400レスポンスへ変換する。
     */
    public ResponseEntity<ErrorResponse> validation(MethodArgumentNotValidException exception,
                                                     HttpServletRequest request) {
        List<ErrorDetail> details = exception.getBindingResult().getFieldErrors().stream()
                .map(error -> new ErrorDetail(error.getField(), error.getDefaultMessage()))
                .toList();
        String requestId = requestId(request);
        LOGGER.warn("event=business.error requestId={} feature={} useCase={} status={} code={} detailCount={}",
                requestId, RequestContext.feature(request), RequestContext.useCase(request),
                HttpStatus.BAD_REQUEST.value(), "VALIDATION_ERROR", details.size());
        return errorResponse(HttpStatus.BAD_REQUEST, "VALIDATION_ERROR", "入力内容に誤りがあります。", details,
                requestId);
    }

    @ExceptionHandler(MethodArgumentTypeMismatchException.class)
    /**
     * URLパラメータ等の型変換失敗を、入力項目名付きの共通400レスポンスへ変換する。
     */
    public ResponseEntity<ErrorResponse> argumentTypeMismatch(MethodArgumentTypeMismatchException exception,
                                                               HttpServletRequest request) {
        String fieldName = exception.getName() != null ? exception.getName() : "request";
        String requestId = requestId(request);
        List<ErrorDetail> details = List.of(new ErrorDetail(fieldName, "形式が正しくありません。"));
        LOGGER.warn("event=business.error requestId={} feature={} useCase={} status={} code={} detailCount={}",
                requestId, RequestContext.feature(request), RequestContext.useCase(request),
                HttpStatus.BAD_REQUEST.value(), "VALIDATION_ERROR", details.size());
        return errorResponse(HttpStatus.BAD_REQUEST, "VALIDATION_ERROR", "入力内容に誤りがあります。", details,
                requestId);
    }

    @ExceptionHandler(ApiException.class)
    /**
     * 業務処理が投げたAPI例外を、指定されたステータスと詳細を持つレスポンスへ変換する。
     */
    public ResponseEntity<ErrorResponse> apiException(ApiException exception, HttpServletRequest request) {
        String requestId = requestId(request);
        LOGGER.warn("event=business.error requestId={} feature={} useCase={} status={} code={} detailCount={}",
                requestId, RequestContext.feature(request), RequestContext.useCase(request),
                exception.status().value(), exception.code(), exception.details().size());
        return errorResponse(exception.status(), exception.code(), exception.getMessage(), exception.details(), requestId);
    }

    @ExceptionHandler({HttpMessageNotReadableException.class, MissingServletRequestParameterException.class,
        MissingPathVariableException.class})
    /**
     * JSON形式不正や必須パラメータ不足を、利用者起因の共通400レスポンスへ変換する。
     */
    public ResponseEntity<ErrorResponse> invalidRequest(Exception exception, HttpServletRequest request) {
        String requestId = requestId(request);
        LOGGER.warn("event=business.error requestId={} feature={} useCase={} status={} code={} detailCount={}",
                requestId, RequestContext.feature(request), RequestContext.useCase(request),
                HttpStatus.BAD_REQUEST.value(), "INVALID_REQUEST", 0);
        return errorResponse(HttpStatus.BAD_REQUEST, "INVALID_REQUEST", "入力内容に誤りがあります。", List.of(), requestId);
    }

    @ExceptionHandler(Exception.class)
    /**
     * 想定外の例外は内部情報を隠した共通500レスポンスへ変換し、詳細はサーバーログだけへ残す。
     */
    public ResponseEntity<ErrorResponse> unexpected(Exception exception, HttpServletRequest request) {
        String requestId = requestId(request);
        LOGGER.error("event=system.unhandled_exception requestId={} feature={} useCase={} status={} code={} exceptionType={} exceptionTrace={}",
                requestId, RequestContext.feature(request), RequestContext.useCase(request),
                HttpStatus.INTERNAL_SERVER_ERROR.value(), "INTERNAL_SERVER_ERROR", ExceptionLog.type(exception),
                ExceptionLog.stack(exception));
        return errorResponse(HttpStatus.INTERNAL_SERVER_ERROR, "INTERNAL_SERVER_ERROR",
                "システムエラーが発生しました。", List.of(), requestId);
    }

    private ResponseEntity<ErrorResponse> errorResponse(HttpStatus status, String code, String message,
                                                         List<ErrorDetail> details, String requestId) {
        return ResponseEntity.status(status).body(new ErrorResponse(code, message, details, requestId));
    }

    private String requestId(HttpServletRequest request) {
        String requestId = RequestContext.requestId(request);
        if (RequestContext.UNKNOWN.equals(requestId)) {
            requestId = java.util.UUID.randomUUID().toString();
            request.setAttribute(RequestContext.REQUEST_ID_ATTRIBUTE, requestId);
        }
        return requestId;
    }
}

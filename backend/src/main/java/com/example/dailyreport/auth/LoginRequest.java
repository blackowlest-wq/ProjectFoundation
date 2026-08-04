/**
 * ログインAPIの入力値。
 * バックエンドを正とするため、ログインID・パスワードの形式と長さをここで検証する。
 */
package com.example.dailyreport.auth;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

public record LoginRequest(
        @NotBlank(message = "auth.login_id.required")
        @Size(max = 80, message = "auth.login_id.max_length")
        @Pattern(regexp = "^[A-Za-z0-9]+$", message = "auth.login_id.invalid_format")
        String loginId,
        @NotBlank(message = "auth.password.required")
        @Size(max = 100, message = "auth.password.max_length")
        @Pattern(regexp = "^[A-Za-z0-9]+$", message = "auth.password.invalid_format")
        String password
) {
}

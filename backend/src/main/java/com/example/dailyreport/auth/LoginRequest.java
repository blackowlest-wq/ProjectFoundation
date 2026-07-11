/**
 * ログインAPIの入力値。
 * バックエンドを正とするため、ログインID・パスワードの形式と長さをここで検証する。
 */
package com.example.dailyreport.auth;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

public record LoginRequest(
        @NotBlank(message = "ログインIDは必須です。")
        @Size(max = 80, message = "ログインIDは80文字以内で入力してください。")
        @Pattern(regexp = "^[A-Za-z0-9]+$", message = "ログインIDは半角英数字で入力してください。")
        String loginId,
        @NotBlank(message = "パスワードは必須です。")
        @Size(max = 100, message = "パスワードは100文字以内で入力してください。")
        @Pattern(regexp = "^[A-Za-z0-9]+$", message = "パスワードは半角英数字で入力してください。")
        String password
) {
}

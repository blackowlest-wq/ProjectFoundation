/**
 * システム内の利用者ロール。
 * 認証後の初期画面、日報APIの利用可否、将来の承認機能の権限判断で使う。
 */
package com.example.dailyreport.auth;

public enum Role {
    EMPLOYEE,
    MANAGER,
    ADMIN
}

/**
 * 日報管理システムのSpring Boot起動クラス。
 * アプリケーション全体のコンポーネントスキャンと自動設定の入口になる。
 */
package com.example.dailyreport;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class DailyReportApplication {
    /**
     * Spring Bootアプリケーションを起動する。
     */
    public static void main(String[] args) {
        SpringApplication.run(DailyReportApplication.class, args);
    }
}

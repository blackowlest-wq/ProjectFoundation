/**
 * 画面表示・APIエラーのメッセージカタログをOracleから読み込むRepository。
 */
package com.example.dailyreport.master;

import java.util.LinkedHashMap;
import java.util.Map;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

@Repository
public class MessageCatalogRepository {
    private final JdbcTemplate jdbcTemplate;

    public MessageCatalogRepository(JdbcTemplate jdbcTemplate) {
        this.jdbcTemplate = jdbcTemplate;
    }

    /**
     * 指定ロケールの有効なメッセージをキー順で読み込む。
     */
    public Map<String, String> findAll(String locale) {
        return jdbcTemplate.query("""
                SELECT message_key, message_text
                FROM message_catalog
                WHERE locale = ? AND enabled = 1
                ORDER BY message_key
                """, rs -> {
            Map<String, String> messages = new LinkedHashMap<>();
            while (rs.next()) {
                messages.put(rs.getString("message_key"), rs.getString("message_text"));
            }
            return messages;
        }, locale);
    }
}

/**
 * 上長が参照・承認できるグループのDBアクセスを担当するRepository。
 */
package com.example.dailyreport.auth;

import java.util.List;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

@Repository
public class ManagerGroupPermissionRepository {
    private final JdbcTemplate jdbcTemplate;

    public ManagerGroupPermissionRepository(JdbcTemplate jdbcTemplate) {
        this.jdbcTemplate = jdbcTemplate;
    }

    /**
     * 指定した上長が参照できるグループIDをDBから取得し、グループID順で返す。
     */
    public List<String> permittedGroupIds(String managerUserId) {
        return jdbcTemplate.queryForList("""
                SELECT group_id
                FROM manager_group_permissions
                WHERE manager_user_id = ?
                ORDER BY group_id
                """, String.class, managerUserId);
    }
}

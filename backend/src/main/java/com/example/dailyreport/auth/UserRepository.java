/**
 * 利用者EntityのSpring Data Repository。
 * 認証時はログインIDから利用者を検索する。
 */
package com.example.dailyreport.auth;

import java.util.Optional;
import org.springframework.data.jpa.repository.JpaRepository;

public interface UserRepository extends JpaRepository<AppUser, String> {
    Optional<AppUser> findByLoginId(String loginId);
}

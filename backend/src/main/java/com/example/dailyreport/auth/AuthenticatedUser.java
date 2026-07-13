/**
 * Spring Securityの認証済みユーザー表現。
 * 業務処理で元のAppUserを参照できるように、UserDetailsにAppUserを保持する。
 */
package com.example.dailyreport.auth;

import java.util.Collection;
import java.util.List;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.userdetails.UserDetails;

public class AuthenticatedUser implements UserDetails {
    private final AppUser user;

    public AuthenticatedUser(AppUser user) {
        this.user = user;
    }

    /**
     * 業務処理で利用する元の利用者Entityを返す。
     */
    public AppUser user() {
        return user;
    }

    @Override
    /**
     * 利用者ロールをSpring SecurityのROLE_形式の権限へ変換する。
     */
    public Collection<? extends GrantedAuthority> getAuthorities() {
        return List.of(new SimpleGrantedAuthority("ROLE_" + user.getRole().name()));
    }

    @Override
    /**
     * 認証に使用する保存済みパスワードハッシュを返す。
     */
    public String getPassword() {
        return user.getPasswordHash();
    }

    @Override
    /**
     * Spring Securityが認証対象として扱うログインIDを返す。
     */
    public String getUsername() {
        return user.getLoginId();
    }
}

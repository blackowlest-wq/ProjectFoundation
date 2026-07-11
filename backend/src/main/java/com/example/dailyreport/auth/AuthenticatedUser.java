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

    public AppUser user() {
        return user;
    }

    @Override
    public Collection<? extends GrantedAuthority> getAuthorities() {
        return List.of(new SimpleGrantedAuthority("ROLE_" + user.getRole().name()));
    }

    @Override
    public String getPassword() {
        return user.getPasswordHash();
    }

    @Override
    public String getUsername() {
        return user.getLoginId();
    }
}

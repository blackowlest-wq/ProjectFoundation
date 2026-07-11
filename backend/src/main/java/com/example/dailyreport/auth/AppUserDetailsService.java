/**
 * Spring SecurityがログインIDから利用者を取得するためのUserDetailsService実装。
 * DB上のAppUserをAuthenticatedUserへ包み、認証基盤へ渡す。
 */
package com.example.dailyreport.auth;

import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.core.userdetails.UsernameNotFoundException;
import org.springframework.stereotype.Service;

@Service
public class AppUserDetailsService implements UserDetailsService {
    private final UserRepository userRepository;

    public AppUserDetailsService(UserRepository userRepository) {
        this.userRepository = userRepository;
    }

    @Override
    public UserDetails loadUserByUsername(String username) throws UsernameNotFoundException {
        // 存在しないログインIDでも認証失敗として扱い、利用者の有無を外部へ露出しない。
        return userRepository.findByLoginId(username)
                .map(AuthenticatedUser::new)
                .orElseThrow(() -> new UsernameNotFoundException("Invalid login id or password."));
    }
}

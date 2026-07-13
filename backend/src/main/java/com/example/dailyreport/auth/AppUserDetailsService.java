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
        // Why not: 存在しないログインIDだけ別応答にすると利用者の有無を推測されるため、認証失敗として同じ扱いにする。
        return userRepository.findByLoginId(username)
                .map(AuthenticatedUser::new)
                .orElseThrow(() -> new UsernameNotFoundException("Invalid login id or password."));
    }
}

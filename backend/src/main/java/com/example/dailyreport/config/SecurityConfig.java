/**
 * Web APIの認証・認可・CSRF設定をまとめる設定クラス。
 * Cookieセッション方式のログイン状態を前提に、保護APIへの未ログインアクセスを拒否する。
 */
package com.example.dailyreport.config;

import com.example.dailyreport.auth.AppUserDetailsService;
import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.List;
import java.util.Map;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.security.authentication.AuthenticationManager;
import org.springframework.security.authentication.ProviderManager;
import org.springframework.security.authentication.dao.DaoAuthenticationProvider;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.HttpStatusEntryPoint;
import org.springframework.security.web.csrf.CookieCsrfTokenRepository;
import org.springframework.security.web.csrf.CsrfTokenRequestAttributeHandler;
import org.springframework.security.web.access.AccessDeniedHandler;

@Configuration
public class SecurityConfig {
    @Bean
    public SecurityFilterChain securityFilterChain(HttpSecurity http, ObjectMapper objectMapper) throws Exception {
        CsrfTokenRequestAttributeHandler csrfHandler = new CsrfTokenRequestAttributeHandler();
        // How: CookieCsrfTokenRepositoryがXSRF-TOKEN Cookieを発行し、SPAは変更系リクエストでX-XSRF-TOKENヘッダーへ返す。
        // Why not: SPAがCookieからCSRFトークンを読む契約を維持するため、リクエスト属性名の遅延解決を無効化する。
        csrfHandler.setCsrfRequestAttributeName(null);

        http
                .csrf(csrf -> csrf
                        // Why not: トークンをレスポンス本文へ埋め込まず、フロントエンドがCookieから読み取り変更系APIのヘッダーへ送る方式に合わせる。
                        .csrfTokenRepository(CookieCsrfTokenRepository.withHttpOnlyFalse())
                        .csrfTokenRequestHandler(csrfHandler)
                        // Why not: ログイン前はCSRFトークンを取得できないため、保護を全APIから外さずログインAPIだけを除外する。
                        .ignoringRequestMatchers("/api/auth/login"))
                .authorizeHttpRequests(auth -> auth
                        .requestMatchers(HttpMethod.POST, "/api/auth/login").permitAll()
                        .anyRequest().authenticated())
                .formLogin(AbstractHttpConfigurer::disable)
                .httpBasic(AbstractHttpConfigurer::disable)
                .logout(AbstractHttpConfigurer::disable)
                .exceptionHandling(exception -> exception
                        .authenticationEntryPoint(new HttpStatusEntryPoint(HttpStatus.UNAUTHORIZED))
                        .accessDeniedHandler(accessDeniedHandler(objectMapper)));
        return http.build();
    }

    private AccessDeniedHandler accessDeniedHandler(ObjectMapper objectMapper) {
        return (request, response, accessDeniedException) -> writeForbiddenResponse(response, objectMapper);
    }

    private void writeForbiddenResponse(HttpServletResponse response, ObjectMapper objectMapper) throws IOException {
        response.setStatus(HttpServletResponse.SC_FORBIDDEN);
        response.setContentType("application/json");
        // Why not: Spring Security標準のHTML/空レスポンスでは画面側のエラー処理を統一できないため、共通JSON形式で返す。
        objectMapper.writeValue(response.getWriter(), Map.of(
                "code", "FORBIDDEN",
                "message", "権限がありません。",
                "details", List.of()));
    }

    @Bean
    public AuthenticationManager authenticationManager(AppUserDetailsService userDetailsService,
                                                       PasswordEncoder passwordEncoder) {
        DaoAuthenticationProvider provider = new DaoAuthenticationProvider();
        provider.setUserDetailsService(userDetailsService);
        provider.setPasswordEncoder(passwordEncoder);
        return new ProviderManager(provider);
    }

    @Bean
    public PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder();
    }
}

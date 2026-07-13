/**
 * Cookieセッション方式の認証APIを提供するController。
 * ログイン、ログアウト、ログイン中利用者取得を担当し、パスワードハッシュはレスポンスに含めない。
 */
package com.example.dailyreport.auth;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;
import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
import org.springframework.security.authentication.AuthenticationManager;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.core.context.SecurityContext;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.web.context.HttpSessionSecurityContextRepository;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/auth")
public class AuthController {
    private final AuthenticationManager authenticationManager;

    public AuthController(AuthenticationManager authenticationManager) {
        this.authenticationManager = authenticationManager;
    }

    @PostMapping("/login")
    public CurrentUserResponse login(@Valid @RequestBody LoginRequest request, HttpServletRequest httpRequest) {
        // How: AuthenticationManagerで認証し、SecurityContextをセッションへ保存してから画面表示用の利用者情報へ変換する。
        Authentication authentication = authenticationManager.authenticate(
                new UsernamePasswordAuthenticationToken(request.loginId(), request.password()));
        establishAuthenticatedSession(httpRequest, authentication);
        return CurrentUserResponse.from(((AuthenticatedUser) authentication.getPrincipal()).user());
    }

    private void establishAuthenticatedSession(HttpServletRequest request, Authentication authentication) {
        SecurityContext context = SecurityContextHolder.createEmptyContext();
        context.setAuthentication(authentication);
        SecurityContextHolder.setContext(context);
        HttpSession session = request.getSession(true);
        // Why not: 認証前のセッションIDを継続利用するとセッション固定攻撃を許すため、ログイン成功時に再発行する。
        request.changeSessionId();
        session.setAttribute(HttpSessionSecurityContextRepository.SPRING_SECURITY_CONTEXT_KEY, context);
    }

    @PostMapping("/logout")
    public ResponseEntity<Void> logout(HttpServletRequest request, HttpServletResponse response) {
        SecurityContextHolder.clearContext();
        HttpSession session = request.getSession(false);
        if (session != null) {
            // Why not: Cookieだけを削除するとサーバー側セッションが残るため、セッションを破棄して保護APIを再利用できないようにする。
            session.invalidate();
        }
        return ResponseEntity.noContent().build();
    }

    @GetMapping("/me")
    public CurrentUserResponse me(@AuthenticationPrincipal AuthenticatedUser principal) {
        return CurrentUserResponse.from(principal.user());
    }
}

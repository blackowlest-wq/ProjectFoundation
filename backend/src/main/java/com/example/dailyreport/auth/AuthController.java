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
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

@RestController
@RequestMapping("/api/auth")
public class AuthController {
    private static final Logger LOGGER = LoggerFactory.getLogger(AuthController.class);
    private final AuthenticationManager authenticationManager;

    public AuthController(AuthenticationManager authenticationManager) {
        this.authenticationManager = authenticationManager;
    }

    @PostMapping("/login")
    /**
     * 認証を実行し、セッションへ認証状態を保存したうえで画面用の利用者情報を返す。
     * 認証失敗時は共通例外ハンドラーへ委ね、認証成功時だけ利用者情報を公開する。
     */
    public CurrentUserResponse login(@Valid @RequestBody LoginRequest request, HttpServletRequest httpRequest) {
        // How: AuthenticationManagerで認証し、SecurityContextをセッションへ保存してから画面表示用の利用者情報へ変換する。
        Authentication authentication = authenticationManager.authenticate(
                new UsernamePasswordAuthenticationToken(request.loginId(), request.password()));
        establishAuthenticatedSession(httpRequest, authentication);
        AuthenticatedUser authenticatedUser = (AuthenticatedUser) authentication.getPrincipal();
        LOGGER.info("event=auth.login_succeeded feature=AUTH useCase=LOGIN userId={}",
                authenticatedUser.user().getUserId());
        return CurrentUserResponse.from(authenticatedUser.user());
    }

    /**
     * 認証情報をSecurityContextとHTTPセッションへ保存し、ログイン成功時にセッションIDを再発行する。
     */
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
    /**
     * SecurityContextを消去し、存在するサーバー側セッションを破棄してログアウトを完了する。
     */
    public ResponseEntity<Void> logout(HttpServletRequest request, HttpServletResponse response) {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        String userId = authentication != null && authentication.getPrincipal() instanceof AuthenticatedUser user
                ? user.user().getUserId()
                : "anonymous";
        SecurityContextHolder.clearContext();
        HttpSession session = request.getSession(false);
        // How: 既存セッションがある場合だけ破棄し、未作成ならログアウト処理をそのまま完了する。
        if (session != null) {
            // Why not: Cookieだけを削除するとサーバー側セッションが残るため、セッションを破棄して保護APIを再利用できないようにする。
            session.invalidate();
        }
        LOGGER.info("event=auth.logout_succeeded feature=AUTH useCase=LOGOUT userId={}", userId);
        return ResponseEntity.noContent().build();
    }

    @GetMapping("/me")
    /**
     * 現在の認証済み利用者を画面表示用レスポンスへ変換して返す。
     */
    public CurrentUserResponse me(@AuthenticationPrincipal AuthenticatedUser principal) {
        return CurrentUserResponse.from(principal.user());
    }
}

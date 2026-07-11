/**
 * ログイン画面コンポーネント。
 * フロント側の簡易入力チェックを行い、最終的な認証結果はバックエンドAPIに委ねる。
 */
import { FormEvent, useState } from 'react';
import { login } from './authApi';
import { LOGIN_ID_MAX_LENGTH, PASSWORD_MAX_LENGTH, validateLoginInput } from './loginValidation';
import type { ApiError } from '../shared/apiClient';
import type { CurrentUser } from './types';

export const LOGIN_FORM_TEXT = {
  brand: '日報管理',
  heading: 'ログイン',
  loginIdLabel: 'ログインID',
  passwordLabel: 'パスワード',
  submit: 'ログイン',
  fallbackError: 'ログインに失敗しました。',
} as const;

export function LoginForm({ onLogin }: { onLogin: (user: CurrentUser) => void }) {
  const [loginId, setLoginId] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');

  async function handleSubmit(event: FormEvent) {
    event.preventDefault();
    setError('');
    const validationError = validateLoginInput(loginId, password);
    if (validationError) {
      // バックエンド検証を正としつつ、明らかな入力不備は送信前に利用者へ返す。
      setError(validationError);
      return;
    }
    try {
      onLogin(await login(loginId, password));
    } catch (e) {
      const apiError = e as ApiError;
      setError(apiError.message ?? LOGIN_FORM_TEXT.fallbackError);
    }
  }

  return (
    <main className="login-screen">
      <form className="login-panel" onSubmit={handleSubmit}>
        <div>
          <p className="eyebrow">{LOGIN_FORM_TEXT.brand}</p>
          <h1>{LOGIN_FORM_TEXT.heading}</h1>
        </div>
        <label>
          {LOGIN_FORM_TEXT.loginIdLabel}
          <input
            value={loginId}
            onChange={(event) => setLoginId(event.target.value)}
            autoComplete="username"
            autoCapitalize="none"
            maxLength={LOGIN_ID_MAX_LENGTH}
            spellCheck={false}
          />
        </label>
        <label>
          {LOGIN_FORM_TEXT.passwordLabel}
          <input
            value={password}
            onChange={(event) => setPassword(event.target.value)}
            type="password"
            autoComplete="current-password"
            maxLength={PASSWORD_MAX_LENGTH}
          />
        </label>
        {error && <p className="error" role="alert">{error}</p>}
        <button type="submit">{LOGIN_FORM_TEXT.submit}</button>
      </form>
    </main>
  );
}

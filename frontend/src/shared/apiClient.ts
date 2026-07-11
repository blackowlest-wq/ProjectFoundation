/**
 * フロントエンド共通のAPIクライアント。
 * Cookieセッション、CSRFヘッダー、JSONエラー処理を集約し、各機能のAPI関数を薄く保つ。
 */
export type ApiError = {
  code: string;
  message: string;
  details: { field: string; message: string }[];
};

export const jsonHeaders = { 'Content-Type': 'application/json' };

export function readCookie(name: string): string | null {
  const prefix = `${name}=`;
  const entry = document.cookie
    .split(';')
    .map((cookie) => cookie.trim())
    .find((cookie) => cookie.startsWith(prefix));
  return entry ? decodeURIComponent(entry.slice(prefix.length)) : null;
}

export async function readError(response: Response): Promise<ApiError> {
  try {
    // バックエンドが返す共通エラー形式を優先して、そのまま画面側へ渡す。
    return (await response.json()) as ApiError;
  } catch {
    if (response.status === 401) {
      return { code: 'UNAUTHORIZED', message: 'ログインが必要です。', details: [] };
    }
    return { code: 'UNKNOWN_ERROR', message: 'リクエストに失敗しました。', details: [] };
  }
}

export async function readJson<T>(response: Response): Promise<T> {
  if (response.ok) {
    return (await response.json()) as T;
  }
  throw await readError(response);
}

export async function getJson<T>(url: string): Promise<T> {
  return readJson<T>(await fetch(url, { credentials: 'include' }));
}

export async function getJsonOrNullOnUnauthorized<T>(url: string): Promise<T | null> {
  const response = await fetch(url, { credentials: 'include' });
  if (response.status === 401) {
    // 起動時のログイン状態確認では、未ログインを例外ではなくnullとして扱う。
    return null;
  }
  return readJson<T>(response);
}

export async function postJson<T>(url: string, body: unknown): Promise<T> {
  return readJson<T>(await fetch(url, {
    method: 'POST',
    headers: jsonHeaders,
    credentials: 'include',
    body: JSON.stringify(body),
  }));
}

export async function putJsonWithCsrf<T>(url: string, body: unknown): Promise<T> {
  return readJson<T>(await fetch(url, {
    method: 'PUT',
    credentials: 'include',
    headers: jsonCsrfHeaders(),
    body: JSON.stringify(body),
  }));
}

export async function postJsonWithCsrf<T>(url: string, body: unknown): Promise<T> {
  return readJson<T>(await fetch(url, {
    method: 'POST',
    credentials: 'include',
    headers: jsonCsrfHeaders(),
    body: JSON.stringify(body),
  }));
}

export async function postNoBodyWithCsrf<T>(url: string): Promise<T> {
  return readJson<T>(await fetch(url, {
    method: 'POST',
    credentials: 'include',
    headers: csrfHeader(),
  }));
}

export async function postNoContentWithCsrf(url: string): Promise<void> {
  const response = await fetch(url, {
    method: 'POST',
    credentials: 'include',
    headers: csrfHeader(),
  });
  if (!response.ok) {
    throw await readError(response);
  }
}

export function csrfHeader(): Record<string, string> | undefined {
  const csrfToken = readCookie('XSRF-TOKEN');
  // Spring SecurityのCookieCsrfTokenRepositoryが発行した値を変更系APIのヘッダーへ戻す。
  return csrfToken ? { 'X-XSRF-TOKEN': csrfToken } : undefined;
}

export function jsonCsrfHeaders(): Record<string, string> {
  return { ...jsonHeaders, ...(csrfHeader() ?? {}) };
}

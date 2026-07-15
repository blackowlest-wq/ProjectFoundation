/**
 * フロントエンド共通のAPIクライアント。
 * Cookieセッション、CSRFヘッダー、JSONエラー処理を集約し、各機能のAPI関数を薄く保つ。
 */
export type ApiError = {
  code: string;
  message: string;
  details: { field: string; message: string }[];
  requestId?: string;
};

export const jsonHeaders = { 'Content-Type': 'application/json' };

/** 指定Cookieを読み取り、URLデコードした値を返す。 */
export function readCookie(name: string): string | null {
  const prefix = `${name}=`;
  const entry = document.cookie
    .split(';')
    .map((cookie) => cookie.trim())
    .find((cookie) => cookie.startsWith(prefix));
  return entry ? decodeURIComponent(entry.slice(prefix.length)) : null;
}

/** API共通エラーを優先して読み取り、本文がない場合はHTTPステータス別のエラーを生成する。 */
export async function readError(response: Response): Promise<ApiError> {
  try {
    // Why not: フロントエンド独自のエラー変換を行うとAPI間で内容がずれるため、バックエンドの共通形式を優先して渡す。
    const payload = await response.json() as Partial<ApiError>;
    const error: ApiError = {
      code: typeof payload.code === 'string' ? payload.code : fallbackErrorCode(response.status),
      message: typeof payload.message === 'string' ? payload.message : fallbackErrorMessage(response.status),
      details: Array.isArray(payload.details) ? payload.details : [],
      requestId: typeof payload.requestId === 'string' && payload.requestId.length > 0
        ? payload.requestId
        : response.headers.get('X-Request-Id') ?? undefined,
    };
    logHttpFailure(response, error);
    return error;
  } catch {
    // How: エラー本文を読めない場合でも401だけは未認証として扱い、それ以外は共通の不明エラーへ落とす。
    const error: ApiError = {
      code: fallbackErrorCode(response.status),
      message: fallbackErrorMessage(response.status),
      details: [],
      requestId: response.headers.get('X-Request-Id') ?? undefined,
    };
    logHttpFailure(response, error);
    return error;
  }
}

/** 成功レスポンスをJSONへ変換し、失敗レスポンスはApiErrorとして送出する。 */
export async function readJson<T>(response: Response): Promise<T> {
  // How: 成功時はJSONを型Tへ変換し、失敗時は共通エラーを読み取って例外として伝播する。
  if (response.ok) {
    return (await response.json()) as T;
  }
  throw await readError(response);
}

/** Cookieセッション付きGETを実行し、JSONレスポンスを返す。 */
export async function getJson<T>(url: string): Promise<T> {
  return readJson<T>(await fetchWithDiagnostics(url, { credentials: 'include' }));
}

/** GETを実行し、401だけは未ログイン状態としてnullへ変換する。 */
export async function getJsonOrNullOnUnauthorized<T>(url: string): Promise<T | null> {
  const response = await fetchWithDiagnostics(url, { credentials: 'include' });
  // How: 起動時の未認証だけをnullへ変換し、その他の失敗はreadJsonへ委譲して例外にする。
  if (response.status === 401) {
    // Why not: 未ログインは起動時に起こり得る通常状態であり、例外表示にするとログイン画面の初期表示をエラー扱いするためnullで返す。
    return null;
  }
  return readJson<T>(response);
}

/** JSON本文を持つCookieセッション付きPOSTを実行する。 */
export async function postJson<T>(url: string, body: unknown): Promise<T> {
  return readJson<T>(await fetchWithDiagnostics(url, {
    method: 'POST',
    headers: jsonHeaders,
    credentials: 'include',
    body: JSON.stringify(body),
  }));
}

/** CSRFヘッダー付きPUTを実行し、JSONレスポンスを返す。 */
export async function putJsonWithCsrf<T>(url: string, body: unknown): Promise<T> {
  return readJson<T>(await fetchWithDiagnostics(url, {
    method: 'PUT',
    credentials: 'include',
    headers: jsonCsrfHeaders(),
    body: JSON.stringify(body),
  }));
}

/** CSRFヘッダー付きJSON POSTを実行する。 */
export async function postJsonWithCsrf<T>(url: string, body: unknown): Promise<T> {
  return readJson<T>(await fetchWithDiagnostics(url, {
    method: 'POST',
    credentials: 'include',
    headers: jsonCsrfHeaders(),
    body: JSON.stringify(body),
  }));
}

/** 本文なしのCSRFヘッダー付きPOSTを実行し、JSONレスポンスを返す。 */
export async function postNoBodyWithCsrf<T>(url: string): Promise<T> {
  return readJson<T>(await fetchWithDiagnostics(url, {
    method: 'POST',
    credentials: 'include',
    headers: csrfHeader(),
  }));
}

/** 本文なしのCSRFヘッダー付きPOSTを実行し、204以外をエラーとして送出する。 */
export async function postNoContentWithCsrf(url: string): Promise<void> {
  const response = await fetchWithDiagnostics(url, {
    method: 'POST',
    credentials: 'include',
    headers: csrfHeader(),
  });
  // How: 204を含む成功応答は終了し、HTTPエラーだけを共通エラーへ変換する。
  if (!response.ok) {
    throw await readError(response);
  }
}

/** CookieからCSRFトークンを読み取り、変更系リクエスト用ヘッダーへ変換する。 */
export function csrfHeader(): Record<string, string> | undefined {
  const csrfToken = readCookie('XSRF-TOKEN');
  // Why not: CSRFトークンを独自生成せず、Spring SecurityのCookieCsrfTokenRepositoryが発行した値を変更系APIへ戻して契約を合わせる。
  return csrfToken ? { 'X-XSRF-TOKEN': csrfToken } : undefined;
}

/** JSON Content-TypeとCSRFヘッダーを組み合わせて返す。 */
export function jsonCsrfHeaders(): Record<string, string> {
  return { ...jsonHeaders, ...(csrfHeader() ?? {}) };
}

function fallbackErrorCode(status: number): string {
  return status === 401 ? 'UNAUTHORIZED' : 'UNKNOWN_ERROR';
}

function fallbackErrorMessage(status: number): string {
  return status === 401 ? 'ログインが必要です。' : 'リクエストに失敗しました。';
}

function logHttpFailure(response: Response, error: ApiError): void {
  if (response.status < 500 && error.code !== 'UNKNOWN_ERROR') {
    return;
  }
  console.error('event=api.http_failure', {
    path: pathOnly(response.url),
    status: response.status,
    code: error.code,
    requestId: error.requestId,
  });
}

async function fetchWithDiagnostics(input: RequestInfo | URL, init?: RequestInit): Promise<Response> {
  try {
    return await fetch(input, init);
  } catch (error) {
    console.error('event=api.network_failure', { path: pathOnly(input) });
    throw error;
  }
}

function pathOnly(input: RequestInfo | URL | string): string {
  const rawUrl = typeof input === 'string' ? input : input instanceof URL ? input.toString() : input.url;
  try {
    return new URL(rawUrl, globalThis.location?.origin ?? 'http://localhost').pathname;
  } catch {
    return '/unknown';
  }
}

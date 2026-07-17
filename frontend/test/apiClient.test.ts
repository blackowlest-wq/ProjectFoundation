// @vitest-environment jsdom

import { afterEach, describe, expect, it, vi } from 'vitest';
import {
  csrfHeader,
  getJson,
  getJsonOrNullOnUnauthorized,
  jsonCsrfHeaders,
  readCookie,
  readError,
  readJson,
} from '../src/shared/apiClient';

describe('apiClient diagnostics and request correlation', () => {
  afterEach(() => {
    document.cookie = 'XSRF-TOKEN=; Max-Age=0; path=/';
    vi.restoreAllMocks();
  });

  it('keeps a business error requestId without logging expected 4xx failures', async () => {
    const consoleError = vi.spyOn(console, 'error').mockImplementation(() => undefined);
    const response = new Response(JSON.stringify({
      code: 'VALIDATION_ERROR',
      message: '入力内容に誤りがあります。',
      details: [],
      requestId: 'request-business-001',
    }), { status: 400, headers: { 'Content-Type': 'application/json' } });

    await expect(readError(response)).resolves.toMatchObject({
      code: 'VALIDATION_ERROR',
      requestId: 'request-business-001',
    });
    expect(consoleError).not.toHaveBeenCalled();
  });

  it('uses the response header and logs only safe fields for a server failure', async () => {
    const consoleError = vi.spyOn(console, 'error').mockImplementation(() => undefined);
    const response = new Response(JSON.stringify({
      code: 'INTERNAL_SERVER_ERROR',
      message: 'システムエラーが発生しました。',
      details: [],
    }), {
      status: 500,
      headers: {
        'Content-Type': 'application/json',
        'X-Request-Id': 'request-system-001',
      },
    });

    await expect(readError(response)).resolves.toMatchObject({
      code: 'INTERNAL_SERVER_ERROR',
      requestId: 'request-system-001',
    });
    expect(consoleError).toHaveBeenCalledWith('event=api.http_failure', expect.objectContaining({
      status: 500,
      code: 'INTERNAL_SERVER_ERROR',
      requestId: 'request-system-001',
    }));
    const loggedContext = consoleError.mock.calls[0]?.[1] as Record<string, unknown>;
    expect(loggedContext).not.toHaveProperty('body');
    expect(loggedContext).not.toHaveProperty('headers');
  });

  it('logs a path-only network failure and rethrows the original error', async () => {
    const consoleError = vi.spyOn(console, 'error').mockImplementation(() => undefined);
    const networkError = new TypeError('network unavailable');
    vi.spyOn(globalThis, 'fetch').mockRejectedValue(networkError);

    await expect(getJson('/api/daily-reports?dateFrom=2026-07-01')).rejects.toBe(networkError);
    expect(consoleError).toHaveBeenCalledWith('event=api.network_failure', {
      path: '/api/daily-reports',
    });
  });

  it('uses fallback fields when an unauthorized JSON body omits common error fields', async () => {
    const response = new Response(JSON.stringify({}), {
      status: 401,
      headers: { 'Content-Type': 'application/json', 'X-Request-Id': 'request-auth-001' },
    });
    await expect(readError(response)).resolves.toMatchObject({
      code: 'UNAUTHORIZED', message: 'ログインが必要です。', details: [], requestId: 'request-auth-001',
    });
  });

  it('uses fallback fields and logs when an error body is not JSON', async () => {
    const consoleError = vi.spyOn(console, 'error').mockImplementation(() => undefined);
    await expect(readError(new Response('not-json', { status: 503 }))).resolves.toMatchObject({
      code: 'UNKNOWN_ERROR', message: 'リクエストに失敗しました。', details: [],
    });
    expect(consoleError).toHaveBeenCalledWith('event=api.http_failure', expect.objectContaining({
      status: 503, code: 'UNKNOWN_ERROR',
    }));
  });

  it('returns successful JSON and converts a 401 response to null', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response(null, { status: 401 }));
    await expect(readJson<{ value: string }>(new Response(JSON.stringify({ value: 'ok' }), { status: 200 })))
      .resolves.toEqual({ value: 'ok' });
    await expect(getJsonOrNullOnUnauthorized('/api/me')).resolves.toBeNull();
  });

  it('returns JSON when getJsonOrNullOnUnauthorized receives a non-401 response', async () => {
    vi.spyOn(globalThis, 'fetch').mockResolvedValue(new Response(JSON.stringify({ value: 'ok' }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    }));

    await expect(getJsonOrNullOnUnauthorized<{ value: string }>('/api/me')).resolves.toEqual({ value: 'ok' });
  });

  it('reads and applies the encoded CSRF cookie', () => {
    document.cookie = 'XSRF-TOKEN=token%2B1; path=/';
    expect(readCookie('XSRF-TOKEN')).toBe('token+1');
    expect(csrfHeader()).toEqual({ 'X-XSRF-TOKEN': 'token+1' });
    expect(jsonCsrfHeaders()).toEqual({ 'Content-Type': 'application/json', 'X-XSRF-TOKEN': 'token+1' });
  });

  it('keeps JSON headers when the CSRF cookie is missing', () => {
    expect(readCookie('XSRF-TOKEN')).toBeNull();
    expect(csrfHeader()).toBeUndefined();
    expect(jsonCsrfHeaders()).toEqual({ 'Content-Type': 'application/json' });
  });

  it('logs an unknown path when a network request has an invalid URL', async () => {
    const consoleError = vi.spyOn(console, 'error').mockImplementation(() => undefined);
    vi.spyOn(globalThis, 'fetch').mockRejectedValue(new TypeError('network unavailable'));
    await expect(getJson('http://[invalid')).rejects.toThrow('network unavailable');
    expect(consoleError).toHaveBeenCalledWith('event=api.network_failure', { path: '/unknown' });
  });
});

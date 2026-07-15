import { afterEach, describe, expect, it, vi } from 'vitest';
import { getJson, readError } from '../src/shared/apiClient';

describe('apiClient diagnostics and request correlation', () => {
  afterEach(() => {
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
});

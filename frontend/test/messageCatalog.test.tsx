// @vitest-environment jsdom

import { act } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { MessageProvider, useMessage } from '../src/shared/messageCatalog';

let root: Root | null = null;
let container: HTMLDivElement | null = null;

(globalThis as typeof globalThis & { IS_REACT_ACT_ENVIRONMENT: boolean }).IS_REACT_ACT_ENVIRONMENT = true;

function Probe() {
  return <p>{useMessage('test.message', '既定のメッセージ')}</p>;
}

function jsonResponse(body: unknown, init: ResponseInit = {}) {
  return new Response(JSON.stringify(body), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
    ...init,
  });
}

function render() {
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  act(() => {
    root?.render(
      <MessageProvider>
        <Probe />
      </MessageProvider>,
    );
  });
}

describe('MessageProvider', () => {
  afterEach(() => {
    act(() => root?.unmount());
    container?.remove();
    root = null;
    container = null;
    vi.unstubAllGlobals();
  });

  it('uses the DB catalog text after the authenticated catalog request succeeds', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(jsonResponse({
      locale: 'ja-JP',
      messages: { 'test.message': 'DB設定のメッセージ' },
    })));

    render();
    expect(container?.textContent).toBe('既定のメッセージ');
    await act(async () => {
      await Promise.resolve();
    });

    expect(container?.textContent).toBe('DB設定のメッセージ');
  });

  it('keeps source fallback text when the catalog request fails', async () => {
    vi.stubGlobal('fetch', vi.fn().mockRejectedValue(new Error('catalog unavailable')));

    render();
    await act(async () => {
      await Promise.resolve();
    });

    expect(container?.textContent).toBe('既定のメッセージ');
  });
});

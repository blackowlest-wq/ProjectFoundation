import { afterEach, describe, expect, it, vi } from 'vitest';
import { act } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { LOGIN_FORM_TEXT, LoginForm } from '../src/auth/LoginForm';
import { LOGIN_ID_MAX_LENGTH, PASSWORD_MAX_LENGTH } from '../src/auth/loginValidation';
import type { CurrentUser } from '../src/auth/types';

const currentUser: CurrentUser = {
  userId: 'U001',
  loginId: 'employee001',
  userName: '山田 太郎',
  role: 'EMPLOYEE',
  groupId: 'G001',
  groupName: '第1開発グループ',
  breakTypeId: 'BT001',
  breakTypeName: '標準休憩',
  workTimeTypeId: 'WT001',
  workTimeTypeName: '通常勤務',
};

let root: Root | null = null;
let container: HTMLDivElement | null = null;

(globalThis as typeof globalThis & { IS_REACT_ACT_ENVIRONMENT: boolean }).IS_REACT_ACT_ENVIRONMENT = true;

function renderLoginForm(onLogin = vi.fn()) {
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  act(() => {
    root?.render(<LoginForm onLogin={onLogin} />);
  });
  return { container, onLogin };
}

function inputByLabel(labelText: string): HTMLInputElement {
  const labels = Array.from(document.querySelectorAll('label'));
  const label = labels.find((candidate) => candidate.textContent?.includes(labelText));
  if (!label) {
    throw new Error(`Label not found: ${labelText}`);
  }
  const input = label.querySelector('input');
  if (!input) {
    throw new Error(`Input not found: ${labelText}`);
  }
  return input;
}

function change(input: HTMLInputElement, value: string) {
  act(() => {
    const valueSetter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')?.set;
    valueSetter?.call(input, value);
    input.dispatchEvent(new Event('input', { bubbles: true }));
  });
}

function jsonResponse(body: unknown, init: ResponseInit = {}) {
  return new Response(JSON.stringify(body), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
    ...init,
  });
}

async function submit() {
  const form = document.querySelector('form');
  if (!form) {
    throw new Error('Form not found.');
  }
  await act(async () => {
    form.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
    await Promise.resolve();
  });
}

describe('LoginForm', () => {
  afterEach(() => {
    act(() => {
      root?.unmount();
    });
    container?.remove();
    root = null;
    container = null;
    vi.unstubAllGlobals();
  });

  it('uses shared login labels and input limits', () => {
    renderLoginForm();

    expect(document.querySelector('h1')?.textContent).toBe(LOGIN_FORM_TEXT.heading);
    expect(inputByLabel(LOGIN_FORM_TEXT.loginIdLabel).maxLength).toBe(LOGIN_ID_MAX_LENGTH);
    expect(inputByLabel(LOGIN_FORM_TEXT.passwordLabel).maxLength).toBe(PASSWORD_MAX_LENGTH);
  });

  it('shows validation errors before calling the login API', async () => {
    const fetchMock = vi.fn();
    vi.stubGlobal('fetch', fetchMock);
    renderLoginForm();

    await submit();

    expect(document.querySelector('[role="alert"]')?.textContent).toBe('ログインIDは必須です。');
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('submits valid credentials and notifies the parent', async () => {
    const onLogin = vi.fn();
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(new Response(JSON.stringify(currentUser), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    })));
    renderLoginForm(onLogin);

    change(inputByLabel(LOGIN_FORM_TEXT.loginIdLabel), 'employee001');
    change(inputByLabel(LOGIN_FORM_TEXT.passwordLabel), 'password');
    await submit();

    expect(onLogin).toHaveBeenCalledWith(currentUser);
  });

  it('shows the API error message when login fails', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(jsonResponse({
      code: 'AUTHENTICATION_FAILED',
      message: 'ログインIDまたはパスワードが正しくありません。',
      details: [],
    }, { status: 401 })));
    renderLoginForm();

    change(inputByLabel(LOGIN_FORM_TEXT.loginIdLabel), 'employee001');
    change(inputByLabel(LOGIN_FORM_TEXT.passwordLabel), 'wrong');
    await submit();

    expect(document.querySelector('[role="alert"]')?.textContent)
      .toBe('ログインIDまたはパスワードが正しくありません。');
  });
});

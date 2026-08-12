import { act, type ReactNode } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { vi } from 'vitest';

let root: Root | null = null;
let container: HTMLDivElement | null = null;

(globalThis as typeof globalThis & { IS_REACT_ACT_ENVIRONMENT: boolean }).IS_REACT_ACT_ENVIRONMENT = true;

export async function flushEffects(turns = 6) {
  await act(async () => {
    for (let index = 0; index < turns; index += 1) {
      await Promise.resolve();
    }
  });
}

export async function renderUi(ui: ReactNode) {
  container = document.createElement('div');
  document.body.appendChild(container);
  root = createRoot(container);
  await act(async () => {
    root?.render(<>{ui}</>);
    await Promise.resolve();
  });
  await flushEffects();
}

export function cleanupUi() {
  act(() => {
    root?.unmount();
  });
  container?.remove();
  root = null;
  container = null;
  vi.restoreAllMocks();
  vi.useRealTimers();
  window.history.replaceState(null, '', '/login');
}

export function labelByText(labelText: string): HTMLLabelElement {
  const label = Array.from(document.querySelectorAll('label'))
    .find((candidate) => candidate.textContent?.includes(labelText));
  if (!label) {
    throw new Error(`Label not found: ${labelText}`);
  }
  return label as HTMLLabelElement;
}

export function controlByLabel<T extends HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement>(labelText: string): T {
  const control = labelByText(labelText).querySelector('input, select, textarea');
  if (!control) {
    throw new Error(`Control not found: ${labelText}`);
  }
  return control as T;
}

export function setControlValue(control: HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement, value: string) {
  act(() => {
    const prototype = control instanceof HTMLSelectElement
      ? HTMLSelectElement.prototype
      : control instanceof HTMLTextAreaElement
        ? HTMLTextAreaElement.prototype
        : HTMLInputElement.prototype;
    const setter = Object.getOwnPropertyDescriptor(prototype, 'value')?.set;
    setter?.call(control, value);
    control.dispatchEvent(new Event('input', { bubbles: true }));
    control.dispatchEvent(new Event('change', { bubbles: true }));
  });
}

export function inputByLabel(labelText: string): HTMLInputElement {
  return controlByLabel<HTMLInputElement>(labelText);
}

export function buttonByText(labelText: string): HTMLButtonElement {
  const button = Array.from(document.querySelectorAll('button'))
    .find((candidate) => candidate.textContent?.includes(labelText));
  if (!button) {
    throw new Error(`Button not found: ${labelText}`);
  }
  return button as HTMLButtonElement;
}

export async function click(element: Element | null) {
  if (!element) {
    throw new Error('Element not found');
  }
  await act(async () => {
    element.dispatchEvent(new MouseEvent('click', { bubbles: true }));
    await Promise.resolve();
  });
  await flushEffects();
}

export async function keyDown(element: Element, key: string, options: KeyboardEventInit = {}) {
  await act(async () => {
    element.dispatchEvent(new KeyboardEvent('keydown', { bubbles: true, key, ...options }));
    await Promise.resolve();
  });
  await flushEffects();
}

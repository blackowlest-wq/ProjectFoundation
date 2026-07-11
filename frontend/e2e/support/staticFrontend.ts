import type { Page } from '@playwright/test';
import { readFile } from 'node:fs/promises';
import { extname, join } from 'node:path';

const distDir = join(process.cwd(), 'dist');

const contentTypes: Record<string, string> = {
  '.css': 'text/css',
  '.html': 'text/html',
  '.js': 'text/javascript',
};

export async function mockStaticFrontend(page: Page) {
  await page.route('**/*', async (route) => {
    const url = new URL(route.request().url());
    if (url.pathname.startsWith('/api/')) {
      await route.fallback();
      return;
    }

    const filePath = url.pathname.startsWith('/assets/')
      ? join(distDir, decodeURIComponent(url.pathname.slice(1)))
      : join(distDir, 'index.html');
    const body = await readFile(filePath);
    await route.fulfill({
      body,
      contentType: contentTypes[extname(filePath)] ?? 'application/octet-stream',
    });
  });
}

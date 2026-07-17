import { defineConfig } from 'vitest/config';

export default defineConfig({
  build: {
    emptyOutDir: false,
    reportCompressedSize: false,
  },
  server: {
    proxy: {
      '/api': 'http://127.0.0.1:8080',
    },
  },
  preview: {
    proxy: {
      '/api': 'http://127.0.0.1:8080',
    },
  },
  test: {
    environment: 'jsdom',
    exclude: ['node_modules/**', 'dist/**', 'coverage/**', 'e2e/**'],
    environmentOptions: {
      jsdom: {
        url: 'http://localhost/',
      },
    },
    coverage: {
      provider: 'v8',
      clean: true,
      include: ['src/**/*.{ts,tsx}'],
      reporter: ['text', 'text-summary', 'html', 'json-summary', 'lcov'],
      reportsDirectory: 'coverage',
      reportOnFailure: true,
      thresholds: {
        branches: 85,
        functions: 85,
        lines: 85,
        statements: 85,
      },
    },
  },
});

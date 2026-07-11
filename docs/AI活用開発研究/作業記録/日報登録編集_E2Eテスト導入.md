# 日報登録・編集画面 E2Eテスト導入

## 方針

- Playwright の OSS 版 `@playwright/test` を利用する。
- 有料クラウド実行、外部SaaS、録画保存サービスは利用しない。
- ローカルの Vite dev server を Playwright の `webServer` で起動する。
- 初期E2Eは API を Playwright route でモックし、画面操作としてログイン、日報登録、提出、入力エラー表示を確認する。

## 追加ファイル

| ファイル | 内容 |
| --- | --- |
| `frontend/playwright.config.ts` | Playwright 設定。`frontend/e2e` をテスト対象にし、Vite dev server を起動 |
| `frontend/e2e/daily-report.spec.ts` | 日報登録・提出、入力エラー表示の画面操作テスト |
| `frontend/package.json` | `e2e`、`e2e:headed`、`e2e:install` スクリプトと `@playwright/test` を追加 |
| `frontend/vite.config.ts` | Vitest が `e2e` 配下を拾わないよう除外 |

## 実行手順

ネットワーク接続または社内npmミラーに接続できる環境で、以下を実行する。

```powershell
cd frontend
npm install
npm run e2e:install
npm run e2e
```

ブラウザを表示して確認する場合は以下を実行する。

```powershell
npm run e2e:headed
```

## 初回導入時の実行結果

- `npm.cmd install -D @playwright/test`: 失敗。ネットワークアクセスが OS により拒否された。
- `npm.cmd install -D @playwright/test --offline`: 失敗。npm キャッシュに完全なメタデータがなく解決不可。
- `npm.cmd run e2e`: 失敗。`playwright` コマンド未導入。
- `npm.cmd run typecheck`: 成功。
- `npm.cmd test`: 成功。5ファイル、18件成功。
- `npm.cmd run build`: 成功。

## 保留事項

- `package-lock.json` は `npm install` 実行後に Playwright 依存を含む状態になった。
- 現在のE2Eは画面操作の安定性確認を優先し、APIはモックしている。Oracle 実機バックエンドを使う完全E2Eは別途追加する。

## 2026-06-28 追記

- `npm install` 後の環境で `npm.cmd run e2e` を再実行した。
- 当初の Vite dev server + Playwright `webServer` 方式では、Node 側の起動確認は成功する一方で Chromium から `localhost` / `127.0.0.1` / LAN IP への接続が `ERR_CONNECTION_REFUSED` になった。
- ローカルサーバ接続に依存しないよう、`npm run build` で生成した `frontend/dist` を Playwright route で配信する方式に変更した。
- API は引き続き Playwright route でモックし、画面は production build を使用する。
- `npm.cmd run e2e`: 成功。2 tests passed。
- `npm.cmd run typecheck`: 成功。
- `npm.cmd test -- --run`: 成功。5 files / 18 tests。

## 2026-06-28 追加テストケース追記

- E2E に有給休暇の下書き保存、既存未提出日報の編集、差戻し日報の再提出を追加した。
- フロント単体に入力必須、時刻形式、作業時間最小値、再提出 API、マスタ API の確認を追加した。
- `npm.cmd run e2e`: 成功。5 tests passed。
- `npm.cmd test -- --run`: 成功。5 files / 22 tests。
- `npm.cmd run coverage`: 成功。Statements 89.65%、Branches 86.95%、Functions 96.15%、Lines 89.41%。

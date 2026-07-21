# Daily Report Detail UI Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 日報詳細画面から日報IDを非表示にし、下部操作ボタンの余白と承認状態ピルの全体色を整える。

**Architecture:** 既存の詳細画面コンポーネントと共通CSSだけを変更する。日報IDはJSXから削除し、操作領域には詳細画面専用のラッパー・クラスを追加する。状態ピルは既存の状態クラスを維持したまま、ピル専用の全周ボーダー指定を追加し、カレンダーセルの左ボーダー表現には影響させない。

**Tech Stack:** React 19、TypeScript、Vitest、Vite、既存の `frontend/src/styles.css`。

## Global Constraints

- 承認・差戻しAPI、状態遷移、認可、エラー処理は変更しない。
- 日報詳細の項目、作業明細、既存ボタン文言は変更しない。
- カレンダーセルの状態色と左ボーダー表現は維持する。
- UIテストは `frontend/test` に置き、既存の `DailyReportApprovalPanel.test.tsx` の責務境界を維持する。

---

### Task 1: 日報詳細UIの失敗テストを追加する

**Files:**

- Modify: `frontend/test/DailyReportApprovalPanel.test.tsx`
- Read: `frontend/src/dailyReport/DailyReportDetail.tsx`

**Interfaces:**

- Consumes: `DailyReportDetail`, `managerUser`、`buildReportDetail`、`installFrontendFetch`、`renderUi` from the existing test support.
- Produces: `TC-DUI-001`、`TC-DUI-002`、`TC-DUI-004` のUI回帰テスト。

- [ ] **Step 1: 日報ID非表示テストを書く**

`describe('DailyReport approval panel behavior from task-owned tests', () => { ... })` 内に、次のテストを追加する。

```tsx
it('TC-DUI-001 RT-DUI-001 does not render the report ID below the detail heading', async () => {
  installFrontendFetch({
    reportDetails: {
      'R-PENDING-001': respondJson(buildReportDetail('R-PENDING-001', { approvalStatus: 'PENDING' })),
    },
  });

  await renderUi(<DailyReportDetail user={managerUser} reportId="R-PENDING-001" />);

  expect(document.body.textContent).not.toContain('R-PENDING-001');
  expect(document.body.textContent).toContain('山田 太郎の日報');
});
```

- [ ] **Step 2: 操作領域クラスの失敗テストを書く**

同じテストファイルへ次のテストを追加する。

```tsx
it('TC-DUI-002 RT-DUI-002 keeps approval and navigation actions in separated detail action groups', async () => {
  installFrontendFetch({
    reportDetails: {
      'R-PENDING-001': respondJson(buildReportDetail('R-PENDING-001', { approvalStatus: 'PENDING' })),
    },
  });

  await renderUi(<DailyReportDetail user={managerUser} reportId="R-PENDING-001" />);

  const actionGroups = document.querySelectorAll('.detail-action-groups > .detail-actions');
  expect(actionGroups).toHaveLength(2);
  expect(document.querySelector('[aria-label="承認操作"]')?.textContent).toContain('承認する');
  expect(document.querySelector('[aria-label="詳細画面の遷移"]')?.textContent).toContain('一覧へ戻る');
});
```

- [ ] **Step 3: 既存の状態クラスと操作回帰を確認するテストを書く**

次のテストで、PENDING状態ピルと既存操作の存在を確認する。

```tsx
it('TC-DUI-004 RT-DUI-004 retains the pending status class and approval actions', async () => {
  installFrontendFetch({
    reportDetails: {
      'R-PENDING-001': respondJson(buildReportDetail('R-PENDING-001', { approvalStatus: 'PENDING' })),
    },
  });

  await renderUi(<DailyReportDetail user={managerUser} reportId="R-PENDING-001" />);

  expect(document.querySelector('.status-pill')?.classList.contains('status-pending')).toBe(true);
  expect(buttonByText('承認する')).toBeTruthy();
  expect(buttonByText('差し戻しする')).toBeTruthy();
  expect(Array.from(document.querySelectorAll('a')).some((link) => link.textContent === '一覧へ戻る')).toBe(true);
});
```

- [ ] **Step 4: 追加テストが正しく失敗することを確認する**

Run: `npm.cmd test -- DailyReportApprovalPanel.test.tsx`

Expected: 追加した `TC-DUI-001` は日報IDがまだ表示されるため失敗し、`TC-DUI-002` は `.detail-action-groups` が未実装のため失敗する。既存テストの失敗ではないことを確認する。

### Task 2: 日報詳細UIを最小実装する

**Files:**

- Modify: `frontend/src/dailyReport/DailyReportDetail.tsx:250-320`
- Modify: `frontend/src/styles.css:130-260`

**Interfaces:**

- Consumes: Task 1のDOM契約 `.detail-action-groups`、`.detail-actions`。
- Produces: 日報IDを含まず、操作行を分離した詳細画面DOMと、状態ピル全周色のCSS。

- [ ] **Step 1: 日報IDの表示要素を削除する**

`DailyReportDetail.tsx` の詳細見出し内から次の要素を削除する。

```tsx
<p className="eyebrow">{report.reportId}</p>
```

`<h3>{report.employeeName}の日報</h3>` はそのまま残す。

- [ ] **Step 2: 操作領域を専用ラッパーで囲む**

承認操作と詳細画面遷移の2つの `.actions` を、次の構造になるように変更する。ボタン・リンクの処理、文言、ARIAラベルは変更しない。

```tsx
<div className="detail-action-groups">
  {canChangeStatus && (
    <div className="actions detail-actions" aria-label="承認操作">
      <button
        type="button"
        onClick={(event) => {
          approveTriggerRef.current = event.currentTarget;
          setApprovalDialogOpen(true);
        }}
        disabled={operating || modalOpen}
      >承認する</button>
      <button
        type="button"
        className="secondary"
        onClick={(event) => {
          rejectTriggerRef.current = event.currentTarget;
          setDialogError('');
          setDialogOpen(true);
        }}
        disabled={operating || modalOpen}
      >差し戻しする</button>
    </div>
  )}
  <div className="actions detail-actions" aria-label="詳細画面の遷移">
    {canEdit && <a className="button-link" href={`/daily-reports/${encodeURIComponent(report.reportId)}/edit`}>編集する</a>}
    <a className="button-link secondary-link" href={returnPath}>一覧へ戻る</a>
  </div>
</div>
```

- [ ] **Step 3: 操作間隔と状態ピル全周色を追加する**

`styles.css` に次のCSSを追加する。

```css
.detail-action-groups {
  display: grid;
  gap: 16px;
  margin-top: 8px;
}

.detail-actions {
  gap: 16px;
}

.status-pill.status-draft {
  border-color: #64748b;
}

.status-pill.status-pending {
  border-color: #2563eb;
}

.status-pill.status-rejected {
  border-color: #e11d48;
}

.status-pill.status-approved {
  border-color: #059669;
}
```

`status-draft`、`status-pending`、`status-rejected`、`status-approved` の既存カレンダーセル定義は変更しない。

### Task 3: 実装後の検証と手動確認を行う

**Files:**

- Verify: `frontend/test/DailyReportApprovalPanel.test.tsx`
- Verify: `frontend/src/dailyReport/DailyReportDetail.tsx`
- Verify: `frontend/src/styles.css`

**Interfaces:**

- Consumes: Task 2のDOMとCSS。
- Produces: 受入条件AC-DUI-001～004の検証結果。

- [ ] **Step 1: 対象テストを実行する**

Run: `npm.cmd test -- DailyReportApprovalPanel.test.tsx`

Expected: 対象テストが成功し、日報ID非表示、操作領域、承認状態クラス、承認・差戻し回帰が確認できる。

- [ ] **Step 2: 型チェックと全フロントテストを実行する**

Run: `npm.cmd run typecheck`

Expected: TypeScriptエラーなし。

Run: `npm.cmd test`

Expected: 全テスト成功、失敗0件。

- [ ] **Step 3: production buildを実行する**

Run: `npm.cmd run build`

Expected: `tsc --noEmit` とVite buildが終了コード0で完了する。

- [ ] **Step 4: ブラウザで目視確認する**

Run: `npm.cmd run build` 後に `vite preview` を起動し、上長で `/daily-reports/{reportId}` を開く。

Expected:

- 日報詳細見出し下に `R-...` が表示されない。
- 承認・差戻しと一覧遷移の操作行に16px相当の間隔がある。
- `承認待ち` のステータスピル全体が青系の背景・外枠で表示され、左端だけが濃くならない。

- [ ] **Step 5: 変更内容をコミットする**

```powershell
git add frontend/src/dailyReport/DailyReportDetail.tsx frontend/src/styles.css frontend/test/DailyReportApprovalPanel.test.tsx
git commit -m "fix: polish daily report detail actions"
```

## Self-Review

- SpecのAC-DUI-001～004をTask 1～3へ対応付けた。
- 日報ID、操作余白、ステータスピルの3つの変更を別々の確認項目として定義した。
- API・DB・認可・状態遷移の変更を計画に含めていない。
- テストコードの既存責務境界を維持し、実装コードは2ファイルに限定した。
- `TBD`、`TODO`、曖昧な実装依頼文を含めていない。

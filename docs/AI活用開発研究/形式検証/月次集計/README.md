# F-011 月次集計の形式化

このディレクトリは、F-011（月次集計）について、宣言された仕様と現在の実装から読み取れる仕様を分離してモデル化し、有限モデル検査で差分を確認するための成果物である。

## 入力にした正本

- `docs/AI活用開発研究/サンプル設計書/API一覧.md` A-016
- `docs/AI活用開発研究/サンプル設計書/画面設計.md` S-008
- `docs/AI活用開発研究/サンプル設計書/入力チェック・業務ルール一覧.md` V-OUT-003
- `docs/AI活用開発研究/作業記録/月次集計_テストケース.md` BE-002～015、FE/E2E/Oracleケース
- `backend/src/main/java/com/example/dailyreport/monthlysummary/MonthlySummaryService.java`
- `backend/src/main/java/com/example/dailyreport/monthlysummary/JdbcMonthlySummaryRepository.java`

## モデル

| モデル | 対象 | 形式化した性質 |
| --- | --- | --- |
| `monthly_summary_z3.py` | 文書仕様と実装の関係 | ADMIN限定、`APPROVED`限定、社員／案件／分類／休日の4集計、null分は0、空集合 |
| `MonthlySummaryDeclared.tla` / `.als` | 文書仕様の固定fixture | 承認済み2行と非承認1行から、4配列の期待値を得る |
| `MonthlySummaryCode.tla` / `.als` | 実装仕様 | 4本の照会を順番に行う、`9999-12`の翌月境界、照会間のDB版差し替え |

## 実行

Z3のみPython環境で次を実行する。

```text
python scripts/formal-verification/monthly_summary_z3.py
```

TLA+とAlloyは処理系のJARを引数にする。ダウンロード元・版は環境に依存するため、リポジトリへJARを含めていない。

```text
powershell -File scripts/formal-verification/run-monthly-summary-formal.ps1 `
  -TlaJar <path-to-tla2tools.jar> -AlloyJar <path-to-alloy4.jar>
```

TLCのカウンター例は終了コード1になる。これは検査対象の不変条件が破れたことを表し、ランナーの故障ではない。

## 判定の読み方

- `PASS`: 有限モデルの範囲で反例がない。無限の全入力を証明したものではない。
- `COUNTEREXAMPLE`: モデル化した実装で、要求した不変条件を破る具体状態が存在する。
- 明示仕様にない性質（同一DBスナップショットなど）は「仕様違反」と断定せず、導出した品質仮定として別分類する。

詳細な反例、実行結果、ドメイン用語への戻しは `月次集計_形式検証報告.md` を参照する。

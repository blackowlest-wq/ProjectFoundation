# Task 1 report

- Status: DONE
- Commit: 78d5526

## What changed

- Added `scripts/check-test-layout.ps1` to fail when test files are misplaced under `frontend/src` or `backend/src/main`.
- Added `check:test-layout`, `pretest`, and `precoverage` scripts to `frontend/package.json`.

## Verification

- `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/check-test-layout.ps1` → failed as expected and reported `frontend/src/dailyReport/dailyReportSearch.test.ts`.
- `git diff --check -- scripts/check-test-layout.ps1 frontend/package.json` → passed.

## Fix verification

- Updated frontend matcher from `\.(test|spec)\.[^.]+$` to `\.(test|spec)\..+$` so names like `foo.test.d.ts` and `foo.spec.browser.ts` are caught.

## Notes

- Existing unrelated changes, including `.github/`, were left untouched.

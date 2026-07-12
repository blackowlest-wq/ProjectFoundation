Status: done
Commits: 9f91602
Test summary: `powershell -NoProfile -File scripts/test-oracle.ps1 '-Dtest=DailyReportSeparationTest' 'test'` reaches the intended bean-name assertion failure after Spring Boot starts with Oracle credentials from the local loader.
Concerns: The guard is now exercising the real test profile and DB-backed context; the remaining failure is expected until the separated beans are implemented.

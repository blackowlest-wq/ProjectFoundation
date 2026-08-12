module MonthlySummaryCode

abstract sig Year {}
one sig Y2026, Y9999, Y10000 extends Year {}
abstract sig Month {}
one sig M01, M12 extends Month {}

sig Request {
  year: one Year,
  month: one Month,
  nextMonthYear: one Year
}

abstract sig Version {}
one sig V0, V1 extends Version {}

sig CodeSummary {
  employeeQueryVersion: one Version,
  projectQueryVersion: one Version,
  categoryQueryVersion: one Version,
  holidayQueryVersion: one Version
}

/* Java YearMonth accepts 9999-12 and plusMonths().atDay(1) reaches 10000-01-01. */
fact AcceptedUpperBoundary {
  some r: Request | r.year = Y9999 and r.month = M12 and r.nextMonthYear = Y10000
}

/* The service executes four repository queries without an explicit snapshot
   isolation contract.  A concurrent approval can make these versions differ. */
fact MixedReadIsPossible {
  some s: CodeSummary |
    s.employeeQueryVersion = V0 and
    s.projectQueryVersion = V1 and
    s.categoryQueryVersion = V1 and
    s.holidayQueryVersion = V1
}

assert OracleDateRepresentable {
  all r: Request | r.nextMonthYear != Y10000
}

assert SingleCommittedSnapshot {
  all s: CodeSummary |
    s.employeeQueryVersion = s.projectQueryVersion and
    s.projectQueryVersion = s.categoryQueryVersion and
    s.categoryQueryVersion = s.holidayQueryVersion
}

check OracleDateRepresentable for 6
check SingleCommittedSnapshot for 6

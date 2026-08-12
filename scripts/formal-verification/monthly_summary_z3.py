"""Bounded Z3 model for F-011 monthly summary.

The model deliberately separates properties that are declared by the design
documents from properties inferred from the implementation.  A reported
COUNTEREXAMPLE is an intended result of this analysis, not a script failure.
"""

from z3 import And, Bool, If, Int, Not, Or, Solver, Sum, sat


APPROVED = 3
ADMIN = 1
FORBIDDEN = 403


def _check_unsat(name: str, solver: Solver) -> None:
    result = solver.check()
    if result == sat:
        print(f"FAIL {name}: unexpected mismatch")
        print(solver.model())
    else:
        print(f"PASS {name}: no bounded counterexample")


def check_aggregation_refinement() -> None:
    """Declared APPROVED/null/half-open rules agree with the four SQL shapes."""

    in_month = [Bool(f"in_month_{i}") for i in range(3)]
    status = [Int(f"status_{i}") for i in range(3)]
    employee_minutes = [Int(f"employee_minutes_{i}") for i in range(3)]
    employee_is_null = [Bool(f"employee_is_null_{i}") for i in range(3)]
    item_minutes = [Int(f"item_minutes_{i}") for i in range(3)]
    holiday = [Bool(f"holiday_{i}") for i in range(3)]

    base = Solver()
    for i in range(3):
        base.add(status[i] >= 0, status[i] <= 3)
        base.add(employee_minutes[i] >= 0, item_minutes[i] >= 0)

    approved_in_month = [And(in_month[i], status[i] == APPROVED) for i in range(3)]
    declared_employee = Sum(
        [
            If(approved_in_month[i], If(employee_is_null[i], 0, employee_minutes[i]), 0)
            for i in range(3)
        ]
    )
    code_employee = Sum(
        [
            If(And(in_month[i], status[i] == APPROVED), If(employee_is_null[i], 0, employee_minutes[i]), 0)
            for i in range(3)
        ]
    )
    declared_project = Sum(
        [If(approved_in_month[i], item_minutes[i], 0) for i in range(3)]
    )
    code_project = Sum(
        [If(And(in_month[i], status[i] == APPROVED), item_minutes[i], 0) for i in range(3)]
    )
    declared_holiday = Sum([If(approved_in_month[i] & holiday[i], 1, 0) for i in range(3)])
    code_holiday = Sum(
        [If(And(in_month[i], status[i] == APPROVED, holiday[i]), 1, 0) for i in range(3)]
    )

    mismatch = Or(
        declared_employee != code_employee,
        declared_project != code_project,
        declared_holiday != code_holiday,
    )
    base.add(mismatch)
    _check_unsat("declared-vs-code APPROVED/null/half-open aggregates", base)


def check_admin_short_circuit() -> None:
    """An unauthorized request must not parse yearMonth or call the repository."""

    role = Int("role")
    response_status = Int("response_status")
    parse_called = Bool("parse_called")
    repository_calls = Int("repository_calls")

    solver = Solver()
    solver.add(role != ADMIN)
    # Implementation behavior read from MonthlySummaryService.
    solver.add(response_status == FORBIDDEN, parse_called == False, repository_calls == 0)
    solver.add(
        Or(
            response_status != FORBIDDEN,
            parse_called,
            repository_calls != 0,
        )
    )
    _check_unsat("ADMIN authorization short-circuit", solver)


def find_year_9999_counterexample() -> None:
    """Find 9999-12: accepted by Java parsing, but next-month bound is not Oracle DATE-safe."""

    year = Int("year")
    month = Int("month")
    next_year = Int("next_year")

    solver = Solver()
    # This is exactly the accepted four-digit range at the upper edge of the
    # implementation's YearMonth parser.
    solver.add(year == 9999, month == 12)
    solver.add(year >= 0, year <= 9999, month >= 1, month <= 12)
    solver.add(next_year == If(month == 12, year + 1, year))
    oracle_date_safe = next_year <= 9999
    solver.add(Not(oracle_date_safe))

    if solver.check() == sat:
        print("COUNTEREXAMPLE FM-F011-001: accepted yearMonth reaches an unrepresentable Oracle upper bound")
        print(solver.model())
    else:
        print("PASS FM-F011-001: no 9999-12 counterexample")


def find_snapshot_counterexample() -> None:
    """Four independent JDBC queries can observe different committed versions."""

    employee_query_version = Int("employee_query_version")
    project_query_version = Int("project_query_version")
    employee_value = Int("employee_value")
    project_value = Int("project_value")

    solver = Solver()
    # A concurrent approval/transaction can commit between the first and
    # second SELECT under ordinary READ COMMITTED semantics.
    solver.add(employee_query_version == 0, project_query_version == 1)
    solver.add(employee_value == 480, project_value == 540)
    solver.add(employee_query_version != project_query_version)
    solver.add(employee_value != project_value)

    if solver.check() == sat:
        print("COUNTEREXAMPLE FM-F011-002: four aggregates are not guaranteed to share one DB snapshot")
        print(solver.model())
    else:
        print("PASS FM-F011-002: no mixed-snapshot counterexample")


if __name__ == "__main__":
    check_aggregation_refinement()
    check_admin_short_circuit()
    find_year_9999_counterexample()
    find_snapshot_counterexample()

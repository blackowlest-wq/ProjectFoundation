------------------------------ MODULE MonthlySummaryDeclared ------------------------------
EXTENDS Naturals, TLC, FiniteSets

(***************************************************************************)
(* Bounded executable model of the declared F-011 acceptance fixture.      *)
(* Sources: A-016, S-008, 月次集計_テストケース (BE-002..005).              *)
(***************************************************************************)

Rows == {
    [id |-> "R1", status |-> "APPROVED", employee |-> "E001", employeeMinutes |-> 480,
        project |-> "P001", category |-> "WC001", itemMinutes |-> 420,
        holiday |-> "WORKDAY"],
    [id |-> "R2", status |-> "APPROVED", employee |-> "E002", employeeMinutes |-> 360,
        project |-> "P002", category |-> "WC002", itemMinutes |-> 360,
        holiday |-> "PAID_LEAVE"],
    [id |-> "R3", status |-> "PENDING", employee |-> "E999", employeeMinutes |-> 999,
        project |-> "P999", category |-> "WC999", itemMinutes |-> 999,
        holiday |-> "WORKDAY"]
}

ApprovedRows == {r \in Rows : r.status = "APPROVED"}

(* The response is deliberately represented as keyed tuples.  The values are
   the concrete expected result of the declared fixture, not an implementation
   detail of a particular SQL dialect. *)
DeclaredResponse == [
    yearMonth |-> "2026-06",
    employeeWorkSummaries |-> {
        [id |-> "E001", minutes |-> 480],
        [id |-> "E002", minutes |-> 360]
    },
    projectWorkSummaries |-> {
        [id |-> "P001", minutes |-> 420],
        [id |-> "P002", minutes |-> 360]
    },
    categoryWorkSummaries |-> {
        [id |-> "WC001", minutes |-> 420],
        [id |-> "WC002", minutes |-> 360]
    },
    holidayTypeSummaries |-> {
        [holidayType |-> "WORKDAY", days |-> 1],
        [holidayType |-> "PAID_LEAVE", days |-> 1]
    }
]

ExpectedResponse == DeclaredResponse

VARIABLE dummy
vars == <<dummy>>
Init == dummy = 0
Next == UNCHANGED vars
Spec == Init /\ [][Next]_vars

TypeOK ==
    /\ DeclaredResponse.yearMonth = "2026-06"
    /\ Cardinality(ApprovedRows) = 2
    /\ Cardinality(DeclaredResponse.employeeWorkSummaries) = 2
    /\ Cardinality(DeclaredResponse.projectWorkSummaries) = 2
    /\ Cardinality(DeclaredResponse.categoryWorkSummaries) = 2
    /\ Cardinality(DeclaredResponse.holidayTypeSummaries) = 2

ApprovedOnly ==
    \A r \in Rows : r.status # "APPROVED" => r.id = "R3"

=============================================================================

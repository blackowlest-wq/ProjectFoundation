------------------------------ MODULE MonthlySummaryCode ------------------------------
EXTENDS Naturals, Integers, TLC

(***************************************************************************)
(* Model of the current service/repository interaction.                    *)
(* MonthlySummaryService calls four repository methods in sequence.        *)
(* Java accepts a four-digit 9999-12 value before computing next month.    *)
(***************************************************************************)

Years == {2026, 9999}
Months == {1, 12}

VARIABLES year, month, phase, dbVersion, qEmployee, qProject, qCategory, qHoliday
vars == <<year, month, phase, dbVersion, qEmployee, qProject, qCategory, qHoliday>>

Init ==
    /\ year \in Years
    /\ month \in Months
    /\ phase = 0
    /\ dbVersion = 0
    /\ qEmployee = -1
    /\ qProject = -1
    /\ qCategory = -1
    /\ qHoliday = -1

Query ==
    /\ phase < 4
    /\ phase' = phase + 1
    /\ qEmployee' = IF phase = 0 THEN dbVersion ELSE qEmployee
    /\ qProject' = IF phase = 1 THEN dbVersion ELSE qProject
    /\ qCategory' = IF phase = 2 THEN dbVersion ELSE qCategory
    /\ qHoliday' = IF phase = 3 THEN dbVersion ELSE qHoliday
    /\ UNCHANGED <<year, month, dbVersion>>

(* An approval can commit between two SELECT statements.  The implementation
   has readOnly=true, but no explicit snapshot isolation contract. *)
ConcurrentApproval ==
    /\ phase = 1
    /\ dbVersion = 0
    /\ dbVersion' = 1
    /\ UNCHANGED <<year, month, phase, qEmployee, qProject, qCategory, qHoliday>>

Completion ==
    /\ phase = 4
    /\ UNCHANGED vars

Next == Query \/ ConcurrentApproval \/ Completion
Spec == Init /\ [][Next]_vars

TypeOK ==
    /\ year \in Years
    /\ month \in Months
    /\ phase \in 0..4
    /\ dbVersion \in 0..1
    /\ qEmployee \in {-1, 0, 1}
    /\ qProject \in {-1, 0, 1}
    /\ qCategory \in {-1, 0, 1}
    /\ qHoliday \in {-1, 0, 1}

OracleDateSafe == IF month = 12 THEN year < 9999 ELSE TRUE

QueriesAreCoherent ==
    (qEmployee = -1 \/ qProject = -1 \/ qCategory = -1 \/ qHoliday = -1)
    \/ (qEmployee = qProject /\ qProject = qCategory /\ qCategory = qHoliday)

=============================================================================

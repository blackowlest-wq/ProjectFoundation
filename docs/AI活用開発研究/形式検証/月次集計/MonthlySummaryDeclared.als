module MonthlySummaryDeclared

abstract sig Status {}
one sig APPROVED, PENDING extends Status {}
abstract sig Employee {}
one sig E001, E002, E999 extends Employee {}
abstract sig Project {}
one sig P001, P002, P999 extends Project {}
abstract sig Category {}
one sig WC001, WC002, WC999 extends Category {}
abstract sig HolidayType {}
one sig WORKDAY, PAID_LEAVE extends HolidayType {}
abstract sig Month {}
one sig JUN extends Month {}

abstract sig Item {
  project: one Project,
  category: one Category,
  minutes: one Int
}
one sig I1, I2, I3 extends Item {}

abstract sig Report {
  status: one Status,
  employee: one Employee,
  month: one Month,
  workMinutes: one Int,
  item: one Item,
  holidayType: one HolidayType
}
one sig R1, R2, R3 extends Report {}

one sig Result {
  employeeTotal: Employee -> one Int,
  projectTotal: Project -> one Int,
  categoryTotal: Category -> one Int,
  holidayDays: HolidayType -> one Int
}

fun approvedRows[m: Month]: set Report {
  { r: Report | r.month = m and r.status = APPROVED }
}

fun employeeRows[m: Month, e: Employee]: set Report {
  { r: approvedRows[m] | r.employee = e }
}

fun projectRows[m: Month, p: Project]: set Report {
  { r: approvedRows[m] | r.item.project = p }
}

fun categoryRows[m: Month, c: Category]: set Report {
  { r: approvedRows[m] | r.item.category = c }
}

fact DeclaredFixture {
  R1.status = APPROVED and R1.employee = E001 and R1.workMinutes = 480
  R1.item = I1 and I1.project = P001 and I1.category = WC001 and I1.minutes = 420
  R1.holidayType = WORKDAY

  R2.status = APPROVED and R2.employee = E002 and R2.workMinutes = 360
  R2.item = I2 and I2.project = P002 and I2.category = WC002 and I2.minutes = 360
  R2.holidayType = PAID_LEAVE

  R3.status = PENDING and R3.employee = E999 and R3.workMinutes = 999
  R3.item = I3 and I3.project = P999 and I3.category = WC999 and I3.minutes = 999

  Result.employeeTotal[E001] = 480
  Result.employeeTotal[E002] = 360
  Result.employeeTotal[E999] = 0
  Result.projectTotal[P001] = 420
  Result.projectTotal[P002] = 360
  Result.projectTotal[P999] = 0
  Result.categoryTotal[WC001] = 420
  Result.categoryTotal[WC002] = 360
  Result.categoryTotal[WC999] = 0
  Result.holidayDays[WORKDAY] = 1
  Result.holidayDays[PAID_LEAVE] = 1
}

assert ApprovedOnly {
  all r: Report | r.status != APPROVED implies r not in approvedRows[JUN]
}

assert FourDeclaredViews {
  Result.employeeTotal[E001] = 480 and
  Result.employeeTotal[E002] = 360 and
  Result.projectTotal[P001] = 420 and
  Result.projectTotal[P002] = 360 and
  Result.categoryTotal[WC001] = 420 and
  Result.categoryTotal[WC002] = 360 and
  Result.holidayDays[PAID_LEAVE] = 1
}

check ApprovedOnly for 6 but 4 Int
check FourDeclaredViews for 6 but 4 Int

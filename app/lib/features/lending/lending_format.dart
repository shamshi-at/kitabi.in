/// Date formatting helper shared across the lending ledger and its sheets.
const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Short "2 Jun"-style date used across the lending ledger and its sheets.
String fmtLendingDate(DateTime d) => '${d.day} ${_months[d.month - 1]}';

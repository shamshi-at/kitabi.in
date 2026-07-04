// Pure helpers for lending due-date reminders — kept free of the notification
// plugin so the scheduling *logic* (which id, when) is unit-testable.

/// A stable 31-bit notification id derived from a lending record's UUID, so the
/// same record always maps to the same reminder (and can be cancelled by id
/// when the book is returned).
int reminderIdForRecord(String recordId) => recordId.hashCode & 0x7fffffff;

/// When a due-date reminder fires: 9am local on the due date. (The due date is
/// a calendar day; a mid-morning nudge is the useful moment.)
DateTime reminderTimeFor(DateTime dueDate) =>
    DateTime(dueDate.year, dueDate.month, dueDate.day, 9);

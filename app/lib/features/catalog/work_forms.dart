/// The *suggested* vocabulary for a Work's literary form — "Type" in the UI
/// (Novel, Short stories, Poetry…). Mirrors the API's WORK_FORMS in
/// `api/app/schemas/catalog.py`; keep the two lists identical. A separate axis
/// from genre (owner decision, 16 Jul 2026): one per work, and the primary way
/// Malayalam publishing — and the library filter — organizes books.
///
/// Suggestions, not a gate (owner request, 16 Jul 2026): a reader whose book
/// is a form we didn't think of can type their own, and the server normalises
/// it (case-folded onto a known spelling where one matches) rather than
/// turning it away.
const kWorkForms = [
  'Novel',
  'Short stories',
  'Poetry',
  'Memoir',
  'Biography',
  'Essays',
  'Play',
  'Travelogue',
  "Children's",
  'Graphic novel',
];

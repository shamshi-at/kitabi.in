/// The closed vocabulary for a Work's literary form — "Type" in the UI
/// (Novel, Short stories, Poetry…). Mirrors the API's WORK_FORMS in
/// `api/app/schemas/catalog.py`; the server rejects anything outside it, so
/// keep the two lists identical. A separate axis from genre (owner decision,
/// 16 Jul 2026): one per work, and the primary way Malayalam publishing —
/// and the library filter — organizes books.
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

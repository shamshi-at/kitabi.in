/// The languages Kitabi offers — for a reader's profile (which languages they
/// read) and for tagging a book's language. India's shelf leads (Malayalam
/// first — the app's regional wedge), then the wider world alphabetically,
/// because translation flows let a reader catalogue an original written in
/// any language. Full names, matching what the catalog stores.
const kLanguages = [
  // India's shelf — the regional wedge, in rough order of Kitabi relevance.
  'Malayalam',
  'English',
  'Hindi',
  'Tamil',
  'Kannada',
  'Telugu',
  'Marathi',
  'Bengali',
  'Gujarati',
  'Punjabi',
  'Odia',
  'Assamese',
  'Urdu',
  'Sanskrit',
  // The wider world, alphabetical — where translated originals live.
  'Arabic',
  'Chinese',
  'Czech',
  'Danish',
  'Dutch',
  'Finnish',
  'French',
  'German',
  'Greek',
  'Hebrew',
  'Hungarian',
  'Indonesian',
  'Italian',
  'Japanese',
  'Korean',
  'Norwegian',
  'Persian',
  'Polish',
  'Portuguese',
  'Romanian',
  'Russian',
  'Spanish',
  'Swahili',
  'Swedish',
  'Thai',
  'Turkish',
  'Ukrainian',
  'Vietnamese',
];

/// The full pick-list for a book-language field: the reader's [preferred]
/// profile languages first (in their saved order), then every remaining
/// [kLanguages] entry in canonical order. Preferred entries the app no longer
/// lists are kept — an old book's language must never silently vanish from
/// its own picker.
List<String> languageOptions(List<String> preferred) {
  final seen = <String>{};
  return [
    for (final lang in preferred)
      if (seen.add(lang)) lang,
    for (final lang in kLanguages)
      if (seen.add(lang)) lang,
  ];
}

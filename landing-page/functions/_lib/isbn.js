// ISBN shape checking at the edge.
//
// Deliberately shape ONLY — no checksum, no ISBN-10/13 conversion. That
// arithmetic lives in the API (api/app/services/isbn.py) next to the lookup it
// feeds, and duplicating it here would give us two implementations to keep in
// agreement forever, which is exactly how the ISBN-10 gap opened in the first
// place.
//
// What this is for: /isbn/<something> is an unauthenticated URL a crawler can
// walk with any string at all. Rejecting the obviously-not-an-ISBN ones here
// costs nothing and keeps them off the origin.

const ISBN10 = /^[0-9]{9}[0-9X]$/;
const ISBN13 = /^[0-9]{13}$/;

/**
 * The bare ISBN, or null when the input isn't ISBN-shaped.
 *
 * Accepts hyphenated and spaced forms (the way an ISBN is printed and the way
 * another catalogue would link to us) and a lowercase x check character. The
 * checksum is NOT verified: the catalogue contains misprinted ISBNs that are
 * still the only identifier those editions have, and a URL built from one must
 * still reach its book.
 */
export function cleanIsbn(raw) {
  if (typeof raw !== 'string') return null;
  const stripped = raw.replace(/[^0-9Xx]/g, '').toUpperCase();
  return ISBN10.test(stripped) || ISBN13.test(stripped) ? stripped : null;
}

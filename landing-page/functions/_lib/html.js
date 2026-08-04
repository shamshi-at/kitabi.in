// Escaping and small text helpers for the edge renderer.
//
// Every page on kitabi.in is assembled from template literals here, so escaping
// is not optional and it is not automatic — there is no framework doing it for
// us. The rule is: interpolate through `h` (or `attr` inside an attribute) and
// nothing else. `raw()` marks a string as already-safe HTML and is the ONLY way
// to opt out; if you find yourself reaching for it around anything derived from
// the API, that's the bug.

const ESCAPES = {
  '&': '&amp;',
  '<': '&lt;',
  '>': '&gt;',
  '"': '&quot;',
  "'": '&#39;',
};

class Raw {
  constructor(value) {
    this.value = value;
  }
  toString() {
    return this.value;
  }
}

/** Mark a string as trusted HTML — it will not be escaped when interpolated. */
export function raw(value) {
  return new Raw(value == null ? '' : String(value));
}

/** Escape text for HTML. Null/undefined become the empty string, never "null". */
export function h(value) {
  if (value == null) return '';
  if (value instanceof Raw) return value.value;
  return String(value).replace(/[&<>"']/g, (c) => ESCAPES[c]);
}

/** Escape for an attribute value. Same rules; named separately so call sites read clearly. */
export const attr = h;

/**
 * Tagged template that escapes every interpolation and flattens arrays.
 *
 *   html`<h1>${title}</h1>${cards.map(card)}`
 *
 * Arrays are joined with no separator so `list.map(...)` composes directly,
 * which is how every grid and strip on the site is built.
 */
export function html(strings, ...values) {
  let out = strings[0];
  for (let i = 0; i < values.length; i++) {
    const value = values[i];
    if (Array.isArray(value)) {
      out += value.map((v) => (v instanceof Raw ? v.value : h(v))).join('');
    } else {
      out += h(value);
    }
    out += strings[i + 1];
  }
  return new Raw(out);
}

/** Collapse whitespace and clamp, for meta descriptions and previews. */
export function clamp(text, max) {
  const t = String(text || '')
    .replace(/\s+/g, ' ')
    .trim();
  if (t.length <= max) return t;
  return t.slice(0, max - 1).trimEnd() + '…';
}

/** Drop falsy entries and join — for building "1956 · Malayalam · Novel" lines. */
export function joinDot(parts, sep = ' · ') {
  return parts.filter(Boolean).join(sep);
}

/** "1,402" — thousands separators without pulling in Intl on every render. */
export function num(n) {
  if (n == null) return '';
  return String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
}

/** Percent-encode a path segment, leaving an already-clean slug untouched. */
export function seg(value) {
  return encodeURIComponent(String(value == null ? '' : value));
}

/**
 * The canonical path for a catalog entity. Slug when there is one, id when
 * there isn't — a row whose title romanizes to nothing still needs a URL, and
 * the API resolves both.
 */
export function pathFor(kind, entity) {
  if (!entity) return '/';
  return `/${kind}/${seg(entity.slug || entity.id)}`;
}

export const bookPath = (w) => pathFor('book', w);
export const authorPath = (a) => pathFor('author', a);
export const publisherPath = (p) => pathFor('publisher', p);
export const seriesPath = (s) => pathFor('series', s);

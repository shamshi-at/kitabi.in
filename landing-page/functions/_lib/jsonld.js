// schema.org structured data.
//
// Lifted from the `_og.js` that already served the share pages — that code was
// correct and battle-tested (it omits null fields properly and escapes safely),
// so it gets reused rather than rewritten.
//
// ONE RULE ABOVE ALL: never emit AggregateRating with a zero or invented value.
// Google issues manual actions for fabricated review markup, and most works here
// legitimately have no rating. When there's nothing, the property is absent —
// not zero, not "0", absent.

import { ORIGIN } from './layout.js';
import { authorPath, bookPath, clamp, publisherPath } from './html.js';

const abs = (path) => `${ORIGIN}${path}`;

const FORMATS = {
  paperback: 'https://schema.org/Paperback',
  hardcover: 'https://schema.org/Hardcover',
  ebook: 'https://schema.org/EBook',
};

export function website() {
  return {
    '@context': 'https://schema.org',
    '@type': 'WebSite',
    name: 'Kitabi',
    url: ORIGIN,
    // Earns the sitelinks search box under a branded result.
    potentialAction: {
      '@type': 'SearchAction',
      target: { '@type': 'EntryPoint', urlTemplate: `${ORIGIN}/search?q={search_term_string}` },
      'query-input': 'required name=search_term_string',
    },
  };
}

export function organization() {
  return {
    '@context': 'https://schema.org',
    '@type': 'Organization',
    name: 'Kitabi',
    url: ORIGIN,
    logo: abs('/kitabi-logo.png'),
  };
}

export function breadcrumbList(items) {
  return {
    '@context': 'https://schema.org',
    '@type': 'BreadcrumbList',
    itemListElement: items.map((item, i) => ({
      '@type': 'ListItem',
      position: i + 1,
      name: item.label,
      ...(item.href ? { item: abs(item.href) } : {}),
    })),
  };
}

export function itemList(works, name) {
  return {
    '@context': 'https://schema.org',
    '@type': 'ItemList',
    name,
    numberOfItems: works.length,
    itemListElement: works.map((w, i) => ({
      '@type': 'ListItem',
      position: i + 1,
      url: abs(bookPath(w)),
      name: w.title,
    })),
  };
}

export function book(page) {
  const ld = { '@context': 'https://schema.org', '@type': 'Book', name: page.title };
  ld.url = abs(bookPath(page));

  const authors = (page.authors || []).map((a) => ({
    '@type': 'Person',
    name: a.name,
    url: abs(authorPath(a)),
  }));
  if (authors.length) ld.author = authors;
  if (page.translators?.length) {
    ld.translator = page.translators.map((t) => ({ '@type': 'Person', name: t.name }));
  }
  if (page.language) ld.inLanguage = page.language;
  if (page.first_publish_year) ld.datePublished = String(page.first_publish_year);
  if (page.description) ld.description = clamp(page.description, 500);
  if (page.genres?.length) ld.genre = page.genres.map((g) => g.name);

  const withCover = (page.editions || []).find((e) => e.cover_url);
  if (withCover) ld.image = withCover.cover_url;

  // ONLY when a real rating exists. See the note at the top of this file.
  if (page.rating?.average && page.rating.count > 0) {
    ld.aggregateRating = {
      '@type': 'AggregateRating',
      ratingValue: page.rating.average,
      ratingCount: page.rating.count,
      bestRating: 5,
      worstRating: 1,
    };
  }

  if (page.reviews?.length) {
    ld.review = page.reviews.slice(0, 10).map((r) => ({
      '@type': 'Review',
      author: { '@type': 'Person', name: r.reviewer?.display_name || 'A reader' },
      ...(r.rating
        ? {
            reviewRating: {
              '@type': 'Rating',
              ratingValue: r.rating,
              bestRating: 5,
              worstRating: 1,
            },
          }
        : {}),
      ...(r.text ? { reviewBody: clamp(r.text, 800) } : {}),
    }));
  }

  const examples = (page.editions || [])
    .map((e) => {
      const ex = { '@type': 'Book' };
      if (e.isbn) ex.isbn = e.isbn;
      if (e.page_count) ex.numberOfPages = e.page_count;
      const format = FORMATS[String(e.format || '').toLowerCase()];
      if (format) ex.bookFormat = format;
      if (e.publisher?.name) ex.publisher = { '@type': 'Organization', name: e.publisher.name };
      if (e.year) ex.datePublished = String(e.year);
      return Object.keys(ex).length > 1 ? ex : null;
    })
    .filter(Boolean);
  if (examples.length) ld.workExample = examples;

  return ld;
}

export function person(page) {
  const ld = { '@context': 'https://schema.org', '@type': 'Person', name: page.name };
  ld.url = abs(authorPath(page));
  if (page.bio) ld.description = clamp(page.bio, 500);
  if (page.image_url) ld.image = page.image_url;
  if (page.pen_name && page.pen_name !== page.name) ld.alternateName = page.pen_name;
  if (page.works?.length) {
    ld.knowsAbout = undefined;
    delete ld.knowsAbout;
  }
  return ld;
}

export function publisherOrg(page) {
  const ld = { '@context': 'https://schema.org', '@type': 'Organization', name: page.name };
  ld.url = abs(publisherPath(page));
  if (page.logo_url) ld.logo = page.logo_url;
  return ld;
}

export function collectionPage(name, description, url) {
  return {
    '@context': 'https://schema.org',
    '@type': 'CollectionPage',
    name,
    ...(description ? { description: clamp(description, 500) } : {}),
    url: abs(url),
  };
}

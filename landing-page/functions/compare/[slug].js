// /compare/:slug — Kitabi vs one other app. A slug guides.js doesn't have is a
// real 404, never a thin page.
import { COMPARISON_BY_SLUG } from '../_lib/guides.js';
import { notFound } from '../_lib/layout.js';
import { renderCompare } from '../_lib/pages/guides.js';

export function onRequestGet(context) {
  const comparison = COMPARISON_BY_SLUG.get(context.params.slug);
  return comparison ? renderCompare(comparison) : notFound({ what: 'comparison' });
}

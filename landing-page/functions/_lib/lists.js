// Editorial lists — the highest-ROI artifact on the site, and the only one that
// costs writing rather than engineering.
//
// A list is evergreen, links to a dozen book pages, targets a real query ("where
// to start with Malayalam literature"), and is the thing a person actually
// shares. Ten good ones are a better use of a fortnight than any feature.
//
// They live here rather than in the database because they are CONTENT: writing
// one should be a text edit and a deploy, not a migration and an admin screen.
// Each entry names a book by slug and says why it's on the list — the "why" is
// the whole value, and a list without one is just a filtered query.
//
// A slug that no longer resolves is skipped silently at render time, so a list
// never breaks because a book was merged away.

export const LISTS = [
  {
    slug: 'where-to-start-with-malayalam',
    title: 'Where to start with Malayalam literature',
    intro:
      "If you've never read a Malayalam novel, the canon is intimidating and the recommendations are always the same three books. This is a route through it — ordered not by importance but by how easy they are to fall into, with a note on which translation to look for if you can't read the original.",
    entries: [
      {
        slug: 'balyakalasakhi',
        why: 'Ninety-six pages, and the first thirty will teach you more about how Malayalam prose sounds than any history of it. Basheer wrote the way people talk, which in 1944 was a scandal and is now the reason he is still read.',
      },
      {
        slug: 'chemmeen',
        why: 'The one everyone names, and it earns it. A love story that is really a book about the sea and what a community will do to keep its bargain with it.',
      },
      {
        slug: 'aadujeevitham',
        why: 'The modern one. A Malayali migrant is enslaved on a Saudi goat farm and survives it. Reads like a thriller, sits like a documentary.',
      },
      {
        slug: 'khasakkinte-ithihasam',
        why: 'The book that broke Malayalam fiction open, and the hardest one here — put it fourth, not first. Vijayan translated it himself thirty years later, which makes the English version a rare thing: a translation with the author’s authority.',
      },
      {
        slug: 'randamoozham',
        why: 'The Mahabharata retold from Bhima’s side — the brother nobody writes about, doing the work nobody thanks him for.',
      },
      {
        slug: 'naalukettu',
        why: 'A boy comes back to the ancestral house that disowned his mother. The novel that made M. T. the chronicler of the Malayalam family as it came apart.',
      },
    ],
  },
  {
    slug: 'indian-books-that-travelled',
    title: 'Indian books that travelled — in translation',
    intro:
      'Books that were written in one Indian language and found readers in another, or in English. Translation is the least-credited job in publishing and the reason most of this list is readable by most of the people reading it.',
    entries: [
      { slug: 'aadujeevitham', why: 'Malayalam to English as Goat Days, and onward into Tamil, Hindi and Kannada.' },
      { slug: 'chemmeen', why: 'Reached English in 1962 and became the first Malayalam novel with an international readership.' },
      { slug: 'ponniyin-selvan', why: 'Serialised in Tamil in the 1950s, still being newly translated seventy years later.' },
      { slug: 'pather-panchali', why: 'Bengali, and then — via Ray — a film that carried the book everywhere the book had not reached.' },
    ],
  },
  {
    slug: 'short-books-worth-the-shelf',
    title: 'Short books worth the shelf',
    intro:
      'Under two hundred pages each. A good short novel is not a long one with the middle taken out — it is a different instrument, and these are the ones that prove it.',
    entries: [
      { slug: 'balyakalasakhi', why: 'Ninety-six pages that changed what Malayalam prose was allowed to sound like.' },
      { slug: 'samskara', why: 'A death in a Brahmin agrahara, and nobody will touch the body. Under two hundred pages and it never lets up.' },
      { slug: 'chemmeen', why: 'Two hundred and eighteen pages, one coastline, and an argument about fidelity that has outlived everyone in it.' },
    ],
  },
];

export const LIST_BY_SLUG = new Map(LISTS.map((l) => [l.slug, l]));

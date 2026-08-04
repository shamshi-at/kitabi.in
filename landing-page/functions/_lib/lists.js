// Editorial lists — the highest-ROI artifact on the site, and the only one that
// costs writing rather than engineering.
//
// A list is evergreen, links to a handful of book pages, targets a real query
// ("where to start with Malayalam literature"), and is the thing a person
// actually shares. They live here rather than in the database because they are
// CONTENT: writing one should be a text edit and a deploy, not a migration and
// an admin screen.
//
// TWO RULES FOR WRITING THEM, both learned the hard way:
//
// 1. EVERY SLUG MUST EXIST IN THE CATALOGUE. The first draft of this file was
//    curated against books that ought to be there rather than books that are —
//    chemmeen, balyakalasakhi, khasakkinte-ithihasam — and every entry was
//    silently skipped, leaving a title and an intro over nothing. Check a slug
//    against /public/works?slug=… before adding it. A list needs at least three
//    resolvable entries to render at all (handler.js), so a half-real list is a
//    404, not a thin page.
//
// 2. THE "WHY" MUST BE TRUE. It is the whole value of a list — without it this
//    is a filtered query — but it is also published prose about real books by
//    real people. Do not restate the catalogue's `year` as a first-publication
//    date: those are edition years, and they are frequently the year of a
//    reprint (Crime and Punishment is filed here under 1884, Pather Panchali
//    under 1985). The page renders the year itself; the prose doesn't need to.

export const LISTS = [
  {
    slug: 'where-to-start-with-malayalam',
    title: 'Where to start with Malayalam',
    intro:
      "Malayalam's readership is out of all proportion to the size of the state that produces it, and the writing has the confidence that comes with that. This is a route in — a novel that reads like a thriller, a memoir that caused a scandal, and a poem that is still argued about a century later.",
    entries: [
      {
        slug: 'aatujeevitham',
        why: "Benyamin's novel about a Malayali migrant enslaved on a goat farm in the Saudi desert, and what survival costs him. It became the biggest Malayalam bestseller of its generation and reached English as Goat Days. Start here: it reads like a thriller and sits like a documentary.",
      },
      {
        slug: 'me-grandad-ad-an-elephant',
        why: "Three novellas by Vaikom Muhammad Basheer, who wrote the way people actually talk — a scandal when he began and the reason he is still read. If you only ever read one Malayalam writer, the argument for it being Basheer is that nobody else sounds like anyone at all afterwards.",
      },
      {
        slug: 'enmakaje',
        why: "Ambikasutan Mangad wrote this out of the aerial spraying of endosulfan over Kasaragod and the generation of children it damaged. A novel doing the work that reporting could not get anyone to read.",
      },
      {
        slug: 'amen',
        why: "Sister Jesme's account of decades inside a convent and why she finally left it. It was received less as a memoir than as an accusation, which tells you something about how little of this had been said in Malayalam before.",
      },
      {
        slug: 'francis-ittykkora',
        why: "T. D. Ramakrishnan's sprawl of a novel — secret societies, mathematics, the spice trade, and a great deal that readers argued bitterly about. Divisive on purpose, and a good demonstration that the tradition is not all social realism.",
      },
      {
        slug: 'duravastha',
        why: "Kumaran Asan's narrative poem, in which a Namboodiri woman flees the Malabar violence and shelters with a Pulaya man. Asan put caste at the centre of Malayalam poetry and the argument has not finished.",
      },
    ],
  },
  {
    slug: 'the-world-in-indian-languages',
    title: 'The world, in Indian languages',
    intro:
      'Translation is usually discussed as something that carries Indian books outward. Most of the traffic goes the other way: a reader in Hindi or Bengali has had the world available to them for a very long time, in editions nobody outside the language ever hears about. These are some of them.',
    entries: [
      {
        slug: 'adhi-rata-ki-santanem',
        why: "Rushdie's Midnight's Children in Hindi — a novel about India's independence, written in English, read back into one of the languages it is about.",
      },
      {
        slug: 'ajnabi',
        why: "Camus, in Hindi. A short book about a man who will not perform the grief expected of him, which loses nothing at all in the crossing.",
      },
      {
        slug: 'aparadha-aura-danda',
        why: 'Crime and Punishment in Hindi. Dostoyevsky travels unusually well into Indian languages, and this is the one that everyone reads first.',
      },
      {
        slug: 'atutai-andhu',
        why: 'Margaret Atwood in Bengali — proof that the traffic is contemporary and not only in the classics.',
      },
      {
        slug: 'anne-frank-diary',
        why: 'The diary, in Bengali. One of the most translated books in existence, and a reminder that a catalogue of a language is also a record of what that language chose to bring home.',
      },
      {
        slug: 'autobiography-of-a-yogi',
        why: "Yogananda wrote in English for an American readership and was then translated back into the languages he came from — a strange round trip that says a lot about how Indian spiritual writing reached the world.",
      },
    ],
  },
  {
    slug: 'books-that-crossed-languages',
    title: 'Books that crossed languages',
    intro:
      'Written in one Indian language and read in another. Translation is the least-credited job in publishing and the reason most of this list is reachable by most of the people reading it — so where we know the translator, the book page names them.',
    entries: [
      {
        slug: 'ponniyin-selvan',
        why: "Kalki's Tamil historical epic, serialised in a weekly magazine and read aloud in instalments to people who could not read it themselves. Still being newly translated, which is the surest sign a book has not finished.",
      },
      {
        slug: 'pather-panchali',
        why: "Bibhutibhushan Bandyopadhyay's Bengali novel of a village childhood — and then, through Ray's film, the book that carried Bengali fiction to people who would never read a word of it.",
      },
      {
        slug: 'aatujeevitham',
        why: 'Malayalam into English as Goat Days, and onward into Tamil, Hindi and Kannada. One of the clearest recent cases of an Indian-language novel travelling on its own strength.',
      },
      {
        slug: 'balmiki-ramayana',
        why: 'Ramesh Menon\'s retelling of Valmiki, filed here in Bengali. The Ramayana is the extreme case of a text that has crossed every language it has met and been changed by each one.',
      },
      {
        slug: 'cakuna',
        why: "Krupabai Satthianadhan was among the first Indian women to publish a novel, writing about a Christian girlhood at a time when almost nobody was writing about girlhood at all.",
      },
    ],
  },
];

export const LIST_BY_SLUG = new Map(LISTS.map((l) => [l.slug, l]));

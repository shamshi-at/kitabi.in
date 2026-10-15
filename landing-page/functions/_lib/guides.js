// The app's own pages for the searches people make before they have heard of
// Kitabi — "personal library app", "Goodreads alternative", "Libib vs …",
// "book lending tracker". Before these existed /app was the only page on the
// site about the app at all, and its H1 was the brand name (audit, 16 Oct 2026).
//
// They live here rather than in the database for the reason lists.js gives:
// they are CONTENT, and changing one should be a text edit and a deploy.
//
// THREE RULES FOR WRITING THEM.
//
// 1. A CLAIM ABOUT ANOTHER APP COMES FROM THAT APP'S OWN PAGES, and the page
//    names them under "Sources". Every row below was checked on `checked`
//    against the URLs in `sources`. Anything those pages did not say is left
//    out — not written as "no". Goodreads' help centre would not render for
//    the check, so its page says nothing about lending, owned-books or
//    offline either way; add a row only once it is read from Goodreads itself.
//    Prices and plans drift: re-read the sources and bump `checked` before
//    editing a row. The one row not read off the other app's site is
//    Goodreads' CSV export: api/app/services/import_service.py is built
//    against real Goodreads exports, which is better evidence than a help page.
//
// 2. SAY WHERE THE OTHER APP IS THE BETTER CHOICE. A comparison that only ever
//    finds for us is an advert, readers know it, and answer engines quote the
//    sentence that sounds fair. `betterFor` is required.
//
// 3. KITABI'S SIDE IS WHAT THE SHIPPED APP DOES, in the words /app already
//    uses (landing-page/app.html is the published feature list). Nothing
//    `[WIRED]` or unreleased, and recommendations stay quiet (CLAUDE.md:
//    lending and the library go on the billboard).
//
// Every slug here must also be in sitemap.xml — tests/run.py fails otherwise.

export const CHECKED = '2026-10-16';

// One paragraph that says what Kitabi is, the same everywhere. It is the
// sentence an answer engine lifts when asked "what is Kitabi", so it is kept
// plain and complete rather than clever.
export const KITABI_IN_BRIEF =
  'Kitabi is a free personal library app for iPhone and Android, for readers who own books. ' +
  'Scan a barcode to catalogue a book, keep a lending ledger of who borrowed what, log your ' +
  'reading in pages, and import a Goodreads export. It works offline, shows no ads, and is ' +
  'private by default.';

export const KITABI_FACTS = [
  'Free on iPhone and Android, no ads',
  'Barcode scanning, edition by edition',
  'A free lending ledger with reminders',
  'Reading progress in pages, and a timer',
  'Works offline; syncs when you are back',
  'Malayalam, Tamil and English shelves',
  'Imports a Goodreads or spreadsheet CSV',
];

export const COMPARISONS = [
  {
    slug: 'goodreads',
    name: 'Goodreads',
    title: 'A Goodreads alternative for the books you own — Kitabi',
    h1: 'A Goodreads alternative for the books you actually own',
    description:
      'Kitabi is a free personal library app that imports your Goodreads export, then tracks the copies you own, who borrowed them, and your reading in pages.',
    lede: [
      "Goodreads is built around reading and talking about books: shelves of what you've read, reviews, and a very large community. Kitabi is built around the books on your shelf — the edition you own, the friend who has it, the pages you've read of it.",
      "Plenty of readers keep both. If you want the shelf without the social network, this is what changes.",
    ],
    rows: [
      {
        k: 'Who runs it',
        us: 'An independent app',
        them: 'Goodreads LLC, a subsidiary of Amazon.com, Inc.',
      },
      {
        k: 'Built around',
        us: 'The books you own — editions, loans, your reading log',
        them: 'Reading, reviews and recommendations, with a large community',
      },
      {
        k: 'Advertising',
        us: 'None',
        them: 'Shows interest-based ads, per its privacy policy',
      },
      {
        k: 'Your reviews',
        us: 'Private until you choose to share one',
        them: 'Reviews you post are public',
      },
      {
        k: 'Moving your books',
        us: 'Imports a Goodreads CSV export; exports your whole library as CSV',
        them: 'Lets you export your library as a CSV',
      },
    ],
    sections: [
      {
        h: 'What moves over from Goodreads',
        p: [
          "Export your library from Goodreads as a CSV and import it into Kitabi in one go. Read, currently-reading and to-read become Kitabi's read, reading and wishlist, and your ratings, reviews and the dates you finished books come with them. Books are matched to the catalogue by ISBN where the file has one, so you get that edition rather than a generic listing.",
          "Kitabi doesn't sign in to Goodreads, doesn't post to it and doesn't need you to close your account. The import is a copy of a file you downloaded.",
        ],
      },
      {
        h: 'What Kitabi is built for',
        p: [
          'Ownership. A book on your Kitabi shelf is a specific edition — your 1994 paperback, with its own cover and page count — and you add it by pointing the camera at its barcode.',
          'Lending. Every loan is a dated record: lent to Anu on 2 June, returned. When a book has been out too long, Kitabi reminds you, not them. Books friends lent you sit on a Borrowed shelf.',
          'Reading in pages. Progress is measured against the edition you are holding, sessions can be timed, and a yearly goal counts what you finished.',
          'Indian languages. Malayalam, Tamil and English books sit side by side in their own scripts, search understands transliteration — typing "Kayary" finds കയർ — and translations of the same work stay linked.',
        ],
      },
    ],
    betterFor:
      "If what you want is the conversation — reviews from strangers, friends' updates, a reading challenge to share, and recommendations drawn from a very large community of readers — Goodreads is that, and Kitabi deliberately isn't. Kitabi has no public feed.",
    faq: [
      {
        q: 'Can I move my Goodreads library to Kitabi?',
        a: "Yes. Export your library from Goodreads as a CSV and import it in Kitabi. Shelves, ratings, reviews and reading dates arrive mapped to Kitabi's statuses, and books are matched by ISBN where the file has one.",
      },
      {
        q: 'Do I have to leave Goodreads to use Kitabi?',
        a: "No. Kitabi never connects to your Goodreads account, so you can keep using both — Goodreads for its community, Kitabi for the books you own and lend.",
      },
      {
        q: 'Is Kitabi free?',
        a: 'Yes. Kitabi is free on iPhone and Android, including the lending ledger, and shows no ads.',
      },
      {
        q: 'Are my reviews public on Kitabi?',
        a: 'Not unless you say so. Kitabi is private by default: every visibility switch starts off, and each review has its own. Private notes on a book are never shared.',
      },
    ],
    sources: [
      { label: 'Goodreads — About us', url: 'https://www.goodreads.com/about/us' },
      { label: 'Goodreads — Privacy notice', url: 'https://www.goodreads.com/about/privacy' },
    ],
  },
  {
    slug: 'libib',
    name: 'Libib',
    title: 'Kitabi vs Libib: home library apps compared',
    h1: 'Kitabi vs Libib: which home library app fits your shelf?',
    description:
      'Libib catalogues books, films, music and games, with lending in its paid Pro plan. Kitabi does books only, and its lending ledger is free. How they compare.',
    lede: [
      'Libib is a well-made cataloguing service used by homes, schools and small libraries, and it handles far more than books. Kitabi does one thing — a reader\'s own bookshelf — and puts the parts a reader uses every week, like lending a book to a friend and logging pages read, in the free app.',
    ],
    rows: [
      {
        k: 'Price',
        us: 'Free',
        them: 'Basic is free; Pro is $9 a month or $99 a year (USD)',
      },
      {
        k: 'Lending',
        us: 'Free: a lending ledger with due dates, reminders and a Borrowed shelf',
        them: 'Pro and Ultimate only: a circulation system with patrons, due dates and email notices',
      },
      {
        k: 'What it catalogues',
        us: 'Books',
        them: 'Books, movies, music, video games and board games',
      },
      {
        k: 'Free plan size',
        us: 'One free app, no paid tiers',
        them: 'Basic holds up to 5,000 items in up to 100 collections',
      },
      {
        k: 'Reading',
        us: 'Status and dates, progress in pages, timed reading sessions, a yearly goal',
        them: 'Status (not begun, in progress, completed, abandoned) with start and finish dates',
      },
      {
        k: 'Without a connection',
        us: 'Works offline and syncs later',
        them: 'Its help pages say the app "runs entirely online"',
      },
      {
        k: 'Advertising',
        us: 'None',
        them: 'None',
      },
    ],
    sections: [
      {
        h: 'Lending is the difference',
        p: [
          "On Libib, lending is a library's circulation desk: patrons, holds, kiosks, overdue emails — and it starts with the Pro plan. That is exactly right for a school or a community library.",
          "At home it is usually simpler than that. You lend a novel to a colleague and want to remember you did. Kitabi records it — who, which book, which day — reminds you when it has been out a while, and keeps the record once it comes back. If the friend uses Kitabi too, the book appears on their Borrowed shelf and a return ticks both ledgers. None of it costs anything.",
        ],
      },
      {
        h: 'Reading, not only cataloguing',
        p: [
          "Kitabi tracks reading against the edition you own: the page you're on out of its page count, sessions you time, and the books you finish in a year. Malayalam, Tamil and English books sit in their own scripts, and search understands transliteration.",
        ],
      },
    ],
    betterFor:
      'If you catalogue films, music and games alongside your books, or you run a classroom or community library that needs patrons, holds, kiosks and overdue emails, Libib is built for that and Kitabi is not.',
    faq: [
      {
        q: 'Is lending free on Libib?',
        a: "Not on the free Basic plan. Libib's pricing page lists its lending and circulation system under Pro ($9 a month or $99 a year) and Ultimate. Kitabi's lending ledger is free.",
      },
      {
        q: 'Which is better for a school or community library?',
        a: 'Libib. Its Pro and Ultimate plans have patron records, holds, self-checkout kiosks and email reminders. Kitabi is made for one reader\'s own books.',
      },
      {
        q: 'Which is better for a personal book collection?',
        a: 'If you mostly own books and lend them to friends, Kitabi gives you lending, reading progress and offline use for free. If your collection mixes books with films, music and games, Libib catalogues all of them.',
      },
      {
        q: 'Does Kitabi work offline?',
        a: 'Yes. Your library lives on your phone, so browsing, adding books and logging reading all work without a connection, and sync when you are back online.',
      },
    ],
    sources: [
      { label: 'Libib — Pricing', url: 'https://www.libib.com/pricing' },
      { label: 'Libib support — Lending', url: 'https://support.libib.com/libib/website/lending.html' },
      {
        label: 'Libib support — Mobile app quickstart',
        url: 'https://support.libib.com/getting-started/quickstart-mobile-app.html',
      },
      {
        label: 'Libib support — Item overview',
        url: 'https://support.libib.com/libib/website/library/item-overview.html',
      },
    ],
  },
  {
    slug: 'librarything',
    name: 'LibraryThing',
    title: 'Kitabi vs LibraryThing: personal library apps compared',
    h1: 'Kitabi vs LibraryThing: two ways to catalogue your books',
    description:
      'LibraryThing is a free, web-first catalogue with library-grade data. Kitabi is a free phone app for the books you own — offline, and in any script.',
    lede: [
      'LibraryThing is one of the deepest book-cataloguing services there is: free for any number of books, drawing records from Amazon, the Library of Congress and thousands of other libraries, with a community of nearly three million members.',
      "Kitabi is narrower on purpose. It is a phone app for a reader's own shelf, which keeps working without a connection and treats Malayalam, Tamil and other Indian-language books as first-class.",
    ],
    rows: [
      {
        k: 'Price',
        us: 'Free',
        them: 'Free for any number of books, since March 2020',
      },
      {
        k: 'Where you use it',
        us: 'An iPhone and Android app; every book in the catalogue also has a page on kitabi.in',
        them: 'The website, with apps for iPhone and Android',
      },
      {
        k: 'Lending',
        us: 'A lending ledger with due dates, reminders and a Borrowed shelf; lend to another Kitabi reader and both ledgers update',
        them: 'A lending ("circulation") feature with due dates and overdue status',
      },
      {
        k: 'Catalogue data',
        us: 'A shared catalogue with Indian-language editions, plus barcode scanning and hand entry',
        them: 'Amazon, the Library of Congress and thousands of other libraries',
      },
      {
        k: 'What it catalogues',
        us: 'Books',
        them: 'Books, music and movies',
      },
      {
        k: 'Reading',
        us: 'Progress in pages, timed reading sessions, a yearly goal and charts',
        them: 'Reading progress, charts and statistics',
      },
      {
        k: 'Community',
        us: 'Private by default, with no public feed',
        them: 'Groups, discussion and the Early Reviewers giveaway programme',
      },
    ],
    sections: [
      {
        h: 'Phone first, and offline',
        p: [
          'Kitabi keeps your library on your phone. You can add books, lend them and log reading in a basement or on a train, and it syncs when you are back online. Scanning a barcode is the normal way to add a book, not an extra.',
        ],
      },
      {
        h: 'Indian bookshelves',
        p: [
          'Kitabi grew up on Malayalam, Tamil and English shelves. Titles display in their own script, search understands transliteration — typing "Kayary" finds കയർ — and when you own a book and its translation, Kitabi knows they are the same work.',
        ],
      },
    ],
    betterFor:
      'If you want a library-grade catalogue on a big screen — Dewey or Library of Congress classification, records from thousands of libraries, music and films too, and a large community to talk books with — LibraryThing does far more than Kitabi.',
    faq: [
      {
        q: 'Is LibraryThing free?',
        a: 'Yes. LibraryThing went free for everyone in March 2020, for any number of books.',
      },
      {
        q: 'Does LibraryThing track lending?',
        a: 'Yes. LibraryThing added a lending feature in 2015 that records who has a book, due dates and overdue status. Kitabi has a lending ledger too, with phone reminders and a shelf for books you have borrowed.',
      },
      {
        q: 'Why would I choose Kitabi over LibraryThing?',
        a: 'If you want your library in a phone app that works offline, with reading progress in pages, timed reading sessions, and Malayalam, Tamil and English books handled properly in their own scripts.',
      },
    ],
    sources: [
      { label: 'LibraryThing — About', url: 'https://www.librarything.com/about' },
      { label: 'LibraryThing — Home', url: 'https://www.librarything.com/apps' },
      {
        label: 'LibraryThing blog — New feature: Lending',
        url: 'https://blog.librarything.com/2015/02/new-feature-lending-a-k-a-circulation/',
      },
    ],
  },
];

export const COMPARISON_BY_SLUG = new Map(COMPARISONS.map((c) => [c.slug, c]));

// /lending-tracker — the billboard feature as its own page.
export const LENDING = {
  title: 'Book lending tracker: remember who borrowed your books — Kitabi',
  h1: 'A book lending tracker that remembers who has your books',
  description:
    "Kitabi keeps a free lending ledger for your books: who borrowed which one and when, a reminder when it's time to ask, and a shelf for books friends lent you.",
  lede: [
    "Everyone who owns books has lost one to a friend — not stolen, just never returned, because neither of you remembered. Kitabi keeps a proper ledger instead: who has it, since when, and when it came back.",
  ],
  steps: [
    {
      h: 'Add the book',
      p: 'Point your camera at the barcode, or search for it. It goes on your shelf as the edition you own.',
    },
    {
      h: 'Mark it lent',
      p: 'Write the name of the friend and the day. They do not need the app — a name is enough.',
    },
    {
      h: 'Get a nudge',
      p: 'When a book has been out a while, a quiet notification on your phone reminds you to ask. It goes to you, never to them.',
    },
    {
      h: 'Tick it returned',
      p: 'The loan stays in the ledger — "lent to Anu, 2 June, returned" — so a book\'s travels are remembered.',
    },
  ],
  sections: [
    {
      h: 'Both sides of the ledger',
      p: [
        'Books friends lent you go on a Borrowed shelf, so you remember what to give back as well as what to get back.',
        'If your friend uses Kitabi too, lend to them in the app: the book appears on their Borrowed shelf, and when it comes home a return ticks both ledgers at once.',
      ],
    },
    {
      h: 'A record, not a sticky note',
      p: [
        'Each loan is its own dated entry, so a book lent three times has three loans, each with its own dates. Lending is free in Kitabi — it is the point of the app, not an upgrade.',
      ],
    },
  ],
  faq: [
    {
      q: 'Is the lending tracker free?',
      a: 'Yes. Lending is part of the free app, and the app shows no ads.',
    },
    {
      q: 'Does the person I lend to need Kitabi?',
      a: 'No. A borrower can simply be a name. If they do use Kitabi, you can lend to them in the app and the book appears on their Borrowed shelf.',
    },
    {
      q: 'Will Kitabi message my friend about the book?',
      a: 'No. Reminders are notifications on your own phone. Nothing is sent to the borrower.',
    },
    {
      q: 'Can I keep track of books I have borrowed?',
      a: 'Yes. Books lent to you go on a Borrowed shelf, with who lent them and when.',
    },
    {
      q: 'Does it work offline?',
      a: 'Yes. The ledger lives on your phone and syncs when you are back online.',
    },
  ],
};

// /ml/app — the app, in Malayalam. Kitabi's own first language, and a search
// nobody else is answering. The app's menus are still English (Malayalam
// localisation is on the roadmap), and the FAQ says so rather than letting a
// Malayalam page imply a Malayalam interface.
//
// Written for the owner to review: change the words freely, but keep the
// claims to what the English /app says.
export const MALAYALAM = {
  title: 'Kitabi — വീട്ടിലെ ലൈബ്രറി, ഇനി ഫോണിൽ',
  h1: 'വീട്ടിലെ പുസ്തകശേഖരം ഇനി ഫോണിൽ',
  eyebrow: 'സ്വന്തം ലൈബ്രറിക്കായി ഒരു ആപ്പ്',
  description:
    'സ്വന്തം പുസ്തകങ്ങൾ ബാർകോഡ് സ്കാൻ ചെയ്ത് ചേർക്കാം, ആർക്കൊക്കെ വായിക്കാൻ കൊടുത്തു എന്ന് ഓർത്തുവെക്കാം, വായന പേജുകളായി രേഖപ്പെടുത്താം. സൗജന്യം, പരസ്യങ്ങളില്ല.',
  lede: [
    'Kitabi സ്വന്തമായി പുസ്തകങ്ങളുള്ള വായനക്കാർക്കുള്ള ഒരു ലൈബ്രറി ആപ്പാണ്. മലയാളം, തമിഴ്, ഇംഗ്ലീഷ് പുസ്തകങ്ങൾ ഒരേ ഷെൽഫിൽ, ഓരോന്നും അതിന്റെ സ്വന്തം ലിപിയിൽ. iPhone-ലും Android-ലും സൗജന്യമായി ലഭ്യമാണ്.',
  ],
  features: [
    {
      h: 'ബാർകോഡ് സ്കാൻ ചെയ്താൽ പുസ്തകം ഷെൽഫിൽ',
      p: 'ക്യാമറ പുസ്തകത്തിന്റെ ബാർകോഡിലേക്ക് നീട്ടിയാൽ മതി — പുറംചട്ട, എഴുത്തുകാർ, പ്രസാധകർ, പേജുകളുടെ എണ്ണം എല്ലാം വരും. ബാർകോഡില്ലാത്ത പഴയ പുസ്തകങ്ങൾ തിരഞ്ഞോ കൈകൊണ്ടോ ചേർക്കാം.',
    },
    {
      h: 'വായിക്കാൻ കൊടുത്ത പുസ്തകം ഇനി മറക്കില്ല',
      p: 'ആർക്ക് കൊടുത്തു, എന്ന് കൊടുത്തു, തിരിച്ചു കിട്ടിയോ — ഓരോന്നും തീയതിയോടെ Kitabi ഓർത്തുവെക്കും. ഏറെ നാളായാൽ നിങ്ങളുടെ ഫോണിൽ ഒരു ചെറിയ ഓർമ്മപ്പെടുത്തൽ വരും. കൂട്ടുകാർ തന്ന പുസ്തകങ്ങൾക്ക് പ്രത്യേക ഷെൽഫുമുണ്ട്. ഇതെല്ലാം സൗജന്യം.',
    },
    {
      h: 'വായന, പേജുകളായി',
      p: 'വായിക്കുന്നു, വായിച്ചു, നിർത്തി, വായിക്കണം — ഓരോ പുസ്തകത്തിന്റെയും നില, തുടങ്ങിയതും തീർത്തതുമായ തീയതികൾ, എത്ര പേജായി എന്നത്. വായനയ്ക്ക് ഒരു ടൈമറും ഒരു വർഷത്തെ വായനാലക്ഷ്യവും.',
    },
    {
      h: 'ഏത് ലിപിയിലും തിരയാം',
      p: '"Kayary" എന്ന് ടൈപ്പ് ചെയ്താലും "കയർ" കണ്ടെത്തും. ഒരേ കൃതിയുടെ മൂലവും വിവർത്തനവും നിങ്ങളുടെ ഷെൽഫിലുണ്ടെങ്കിൽ, അവ ഒരേ കഥയാണെന്ന് Kitabi-ക്ക് അറിയാം.',
    },
    {
      h: 'നെറ്റ് ഇല്ലെങ്കിലും',
      p: 'ലൈബ്രറി നിങ്ങളുടെ ഫോണിൽത്തന്നെയാണ്. കണക്ഷനില്ലാത്തപ്പോഴും പുസ്തകങ്ങൾ ചേർക്കാം, വായന രേഖപ്പെടുത്താം; നെറ്റ് തിരിച്ചു വരുമ്പോൾ എല്ലാം സിങ്ക് ആകും.',
    },
    {
      h: 'Goodreads-ൽ നിന്ന് മാറാൻ എളുപ്പം',
      p: 'Goodreads-ൽ നിന്നോ ഒരു സ്പ്രെഡ്ഷീറ്റിൽ നിന്നോ ഉള്ള CSV ഫയൽ ഇംപോർട്ട് ചെയ്താൽ മതി — ഷെൽഫുകളും റേറ്റിംഗുകളും റിവ്യൂകളും തീയതികളും ഒപ്പം വരും.',
    },
  ],
  faq: [
    {
      q: 'Kitabi സൗജന്യമാണോ?',
      a: 'അതെ. പുസ്തകം വായിക്കാൻ കൊടുത്തതിന്റെ കണക്ക് ഉൾപ്പെടെ എല്ലാം സൗജന്യമാണ്. പരസ്യങ്ങളില്ല, നിങ്ങളുടെ വിവരങ്ങൾ ആർക്കും വിൽക്കില്ല.',
    },
    {
      q: 'ആപ്പ് മലയാളത്തിലാണോ?',
      a: 'ഇപ്പോൾ ആപ്പിന്റെ മെനുകളും ബട്ടണുകളും ഇംഗ്ലീഷിലാണ്; മലയാളം പതിപ്പ് ഞങ്ങളുടെ പദ്ധതിയിലുണ്ട്. എന്നാൽ നിങ്ങളുടെ മലയാളം പുസ്തകങ്ങൾ അവയുടെ സ്വന്തം ലിപിയിൽത്തന്നെ കാണാം, മലയാളത്തിലോ ഇംഗ്ലീഷ് അക്ഷരങ്ങളിലോ തിരയാം.',
    },
    {
      q: 'എന്റെ ലൈബ്രറി മറ്റുള്ളവർക്ക് കാണാമോ?',
      a: 'ഇല്ല, നിങ്ങൾ തീരുമാനിക്കാതെ. Kitabi-യിൽ എല്ലാം സ്വതേ സ്വകാര്യമാണ്; ഒരു റിവ്യൂ മാത്രമോ ഷെൽഫ് മുഴുവനോ പങ്കുവെക്കണോ എന്ന് നിങ്ങൾ തീരുമാനിക്കും.',
    },
    {
      q: 'ഏതൊക്കെ ഫോണുകളിൽ കിട്ടും?',
      a: 'iPhone-ലും Android ഫോണുകളിലും. App Store-ലും Google Play-യിലും സൗജന്യമായി ഡൗൺലോഡ് ചെയ്യാം.',
    },
  ],
  cta: {
    h: 'നിങ്ങളുടെ ഷെൽഫ് കാത്തിരിക്കുന്നു',
    p: 'iPhone-ലും Android-ലും സൗജന്യം. പരസ്യങ്ങളില്ല, സ്വകാര്യം.',
    play: 'ഇപ്പോൾ ലഭ്യം',
    apple: 'ഡൗൺലോഡ് ചെയ്യാം',
  },
};

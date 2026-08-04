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
  {
    slug: 'the-malayalam-canon',
    title: 'The Malayalam canon, past the first three books',
    intro:
      'Everyone recommending Malayalam fiction recommends the same handful. Past them is where the tradition actually lives: the street novel, three M. T. novels that are not the famous one, the poet who took the first Jnanpith, and the hangwoman.',
    entries: [
      {
        slug: 'arachchar',
        why: "K. R. Meera's novel about a woman who inherits her family's trade as hangman in Kolkata, and the media circus that forms around her. Long, furious, and the book that put Meera at the front of her generation.",
      },
      {
        slug: 'oru-teruvinre-katha',
        why: "S. K. Pottekkatt takes a single street and writes everyone on it. The Malayalam novel at its most patient — nothing happens quickly and by the end you know a whole neighbourhood.",
      },
      {
        slug: 'kalam',
        why: 'M. T. Vasudevan Nair on ambition and the cost of leaving: a young man gets out of the village he was desperate to escape and finds out what he traded for it.',
      },
      {
        slug: 'olavum-teeravum',
        why: "M. T. again, shorter and harder. He later made it into a film, which is how a good deal of Malayalam fiction reached people who don't read fiction.",
      },
      {
        slug: 'alkkoottattil-taniye',
        why: "The third M. T. here, and the title says the theme he never really left: alone in a crowd. If you want to understand what Malayalam prose sounds like at mid-century, read the three of these together.",
      },
      {
        slug: 'udakappola',
        why: "P. Padmarajan wrote fiction and then wrote and directed some of the best-loved films in the language. The prose has the same quality the films do — you are already inside the situation before you have been told anything about it.",
      },
      {
        slug: 'selected-poems-of-g-sankara-kurup',
        why: 'G. Sankara Kurup took the first Jnanpith ever awarded, which makes him the reason the prize has a Malayalam history at all.',
      },
    ],
  },
  {
    slug: 'premchand-and-the-hindi-novel',
    title: 'Premchand, and what Hindi did next',
    intro:
      'Hindi prose has a founder in a way most literatures do not, and arguing with him has been a full-time occupation ever since. Start with the three Premchands and then the poem every Hindi schoolchild has had to memorise.',
    entries: [
      {
        slug: 'godaan',
        why: "Premchand's last completed novel and the one usually called his best: a peasant who wants one cow, and an economy arranged to ensure he does not get it. The book that made social realism the default setting of Hindi fiction.",
      },
      {
        slug: 'gaban',
        why: 'A clerk, his wife, some borrowed money and a piece of jewellery. Premchand was extremely good at the small compromise that turns out to be the whole life.',
      },
      {
        slug: 'kafan',
        why: "The short story people fight about — two men who will not bury the dead woman in the house, and Premchand refusing to tell you what to think about them. Under twenty pages and it has been argued over for ninety years.",
      },
      {
        slug: 'rashmi-rathi',
        why: "Ramdhari Singh Dinkar's verse retelling of Karna, the Mahabharata's most useful character for anyone who wants to talk about merit and birth without saying so directly.",
      },
    ],
  },
  {
    slug: 'shakespeare-in-hindi',
    title: 'Shakespeare in Hindi',
    intro:
      'Shakespeare arrived in India with the empire and then simply stayed, which is a more interesting fact than it first sounds: the plays were translated, adapted, absorbed into Parsi theatre and eventually into film, and none of that needed the English text to remain in the room.',
    entries: [
      {
        slug: 'maikabetha-ka-padyanuvada',
        why: 'Macbeth, in Hindi verse. A verse translation is a different ambition from a prose one — it accepts that the sound is half the play.',
      },
      {
        slug: 'raja-liar',
        why: 'King Lear. An old man divides his property between his children on the basis of who flatters him best, which travels to any culture with inheritance in it.',
      },
      {
        slug: 'raja-richard-dvitiya',
        why: 'Richard II — much less performed, and the one where Shakespeare is most interested in what a crown is actually made of.',
      },
      {
        slug: 'manamohana-ka-jala',
        why: "A fourth Shakespeare in the catalogue. Four is not an accident; it is what a language looks like when it has been translating someone for a century and a half.",
      },
    ],
  },
  {
    slug: 'detectives-in-translation',
    title: 'Detectives, in translation',
    intro:
      'Crime fiction crosses languages more easily than almost anything else, and it is usually the first thing a publishing industry imports and the first genre it grows its own version of. Both halves are here.',
    entries: [
      {
        slug: 'feluda-one-feluda-two',
        why: "Satyajit Ray wrote the Feluda stories for a Bengali children's magazine while making the films he is known for elsewhere. Generations of Bengali readers met detective fiction through them first.",
      },
      {
        slug: 'himu',
        why: "Humayun Ahmed's Himu — barefoot, yellow-robed, no job, and cleverer than everyone in the room. The most popular character in modern Bangladeshi fiction and nothing like a Western detective.",
      },
      {
        slug: 'pisaca-kutta',
        why: 'The Hound of the Baskervilles in Hindi. Conan Doyle is one of the most-translated authors on earth and this is the one everyone starts with.',
      },
      {
        slug: 'mardara-ona-orienta-eksapresa',
        why: 'Murder on the Orient Express, in Hindi. A closed carriage, a fixed set of suspects, and a solution that only works once — which has not stopped anyone.',
      },
      {
        slug: 'kala-sona',
        why: 'A second Christie in Hindi. She is reliably among the most translated novelists in any language that translates novels at all.',
      },
      {
        slug: 'hand-me-a-fig-leaf-bengali-text',
        why: 'James Hadley Chase in Bengali — the pulpier end of the traffic, and for decades the more widely read end.',
      },
    ],
  },
  {
    slug: 'what-children-read',
    title: 'What children read, across languages',
    intro:
      "A children's list is a good way to see what a language has decided matters, because nobody translates a children's book out of duty. These were carried across because somebody wanted the children in front of them to have it.",
    entries: [
      {
        slug: 'hyari-patara-enda-di-philasapharasa-stona',
        why: "The Philosopher's Stone in Bengali — the first of five here, which is its own small piece of publishing history.",
      },
      {
        slug: 'hyari-patara-ayanda-dya-prijanara-aba-ajakabana',
        why: 'Prisoner of Azkaban. The one most readers name when asked which is best.',
      },
      {
        slug: 'hyari-patara-ayanda-dya-gabaleta-aba-phayara',
        why: 'Goblet of Fire — the book where the series stops being for children and nobody minds.',
      },
      {
        slug: 'hyari-patara-ayanda-dya-hapha-blada-prinsa',
        why: 'Half-Blood Prince, in Bengali.',
      },
      {
        slug: 'hyari-patara-ayanda-dya-dathali-hyalosa',
        why: 'The Deathly Hallows. Five volumes in one language in one catalogue is a fair measure of how completely this travelled.',
      },
      {
        slug: 'pippi-lambemoze',
        why: "Astrid Lindgren's Pippi Longstocking in Hindi — a girl with no parents, no rules and a horse on the veranda, which is a subversive proposition in any language.",
      },
      {
        slug: 'haroun-aur-kahaniyon-ka-samandar',
        why: "Rushdie wrote Haroun and the Sea of Stories for his son while in hiding, and it is a children's book about whether storytelling is allowed to continue. Here it is in Hindi.",
      },
    ],
  },
  {
    slug: 'indian-english-read-back-home',
    title: 'Indian English, read back home',
    intro:
      'Books written in English by Indian writers, translated into Indian languages. The round trip is easy to miss and says something uncomfortable and interesting: for a lot of readers, the English original was never the accessible version.',
    entries: [
      {
        slug: 'mamooli-cheezon-ka-devata',
        why: "The God of Small Things in Hindi. Arundhati Roy's novel is set in Kerala, written in English, and read here in a third language — which is a reasonable description of how Indian publishing actually works.",
      },
      {
        slug: 'malagudi-deza',
        why: "R. K. Narayan's Malgudi in Hindi. Narayan invented a South Indian town in English so completely that it has been re-imported into most of the languages the town would have spoken.",
      },
      {
        slug: 'adhi-rata-ki-santanem',
        why: "Midnight's Children, in Hindi — a novel about India's independence, read back into one of the languages it is about.",
      },
      {
        slug: 'ikshvaku-ke-vamsaja',
        why: 'Amish Tripathi retells the Ramayana in English for a mass readership, and it is promptly translated into the languages the epic already lived in. The circularity is the point.',
      },
      {
        slug: 'vayuputhranmarude-shapadam-malayalam',
        why: 'The same author in Malayalam. Contemporary Indian English fiction now gets translated across the country as a matter of course, which was not true a generation ago.',
      },
    ],
  },
  {
    slug: 'the-european-novel-in-hindi',
    title: 'The European novel, in Hindi',
    intro:
      'Cervantes, Flaubert, Brontë, Zola, Dumas, Kafka, Nabokov — all of them in Hindi, most of them for decades. A catalogue of a language is also a record of what that language decided to go and fetch.',
    entries: [
      {
        slug: 'dana-kvigjota',
        why: 'Don Quixote — arguably the first novel, about a man who has read too many books and believes them. Reasonable place to start anything.',
      },
      {
        slug: 'madama-bovari',
        why: 'Madame Bovary in Hindi. Flaubert on a woman who wants a different life and the provincial arrangement that will not permit one.',
      },
      {
        slug: 'jhanjha-bhavana',
        why: "Wuthering Heights. Emily Brontë's only novel, and still the least comfortable book on most lists of romantic classics.",
      },
      {
        slug: 'kaphka-ki-carcita-kahaniyam',
        why: "Kafka's stories in Hindi — the shorter work, where the machinery is at its most efficient.",
      },
      {
        slug: 'nana',
        why: 'Zola on Paris, money and appetite. He wrote twenty novels to make one argument about heredity and society, and this is among the ones that survived the argument.',
      },
      {
        slug: 'qaidi',
        why: 'Dumas in Hindi. Nobody has ever needed to be persuaded to read a Dumas plot in any language.',
      },
      {
        slug: 'premikaem',
        why: 'D. H. Lawrence, translated into Hindi — an author banned or bowdlerised in his own language for most of his career, quietly available in another.',
      },
    ],
  },
];

export const LIST_BY_SLUG = new Map(LISTS.map((l) => [l.slug, l]));

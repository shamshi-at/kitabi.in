# What people search when they search for books — and what answers it here

Research pass, 9 Aug 2026, feeding the catalogue-discovery work (filters, sorts,
no-dead-end states). Google-trends and industry reporting, mapped to the query
families we can actually serve. Revisit roughly yearly — query fashion moves.

## The query families

| Query family | Evidence | What serves it on Kitabi |
|---|---|---|
| **Genre-first** — "romance books", "crime thrillers malayalam" | Genre browsing is the highest-volume book query shape; romance/fantasy/mystery lead, and Malayalam specifically shows crime-thriller growth | Genre hubs (`/genre/<slug>`, indexed) + genre chips on `/browse` and the app's filter sheet |
| **"Best X"** — "best malayalam novels", "best books 2026" | "best" query intent growing alongside plain genre browsing | `sort=rating` on both browse endpoints — live average over the ratings table; "Top rated" chip on web + app, and the empty-search page's Top-rated door |
| **Short reads** — "short books under 200 pages" | #ShortReads dominated BookTok; Goodreads measured under-300-page adds at twice the usual rate (Jan 2025) | `length=short|medium|long` filter (page-count buckets over editions); chips say the number ("Short · under 200 pp") because that's the phrasing readers type |
| **"Books like X"** | Read-alike services are a whole category (BookBrowse etc.) | "Readers also shelved" on every book page (already shipped) |
| **New / latest** — "latest malayalam novels" | Recurring interest peaks (Jul & Dec for Malayalam novel queries) | `sort=year_desc` (publication) + new `sort=added` (catalogue arrival — the living-shelf feel) |
| **Format/consumption** — audiobooks, ebooks | Fastest-growing formats | Out of scope: Kitabi tracks owned physical/any-format books; not a store |
| **How-to / near-me** | Growing, but transactional | Not our fight |

## Where the leverage actually is

- The **hubs** (`/language/malayalam`, `/language/malayalam/novel`, genre hubs)
  are the pages that win "malayalam novels"-shaped queries — they were already
  indexed; the browse filters now give readers the same cuts *inside* the
  product instead of only via SEO landing pages.
- **`sort=rating` is only as good as the ratings pool.** With a handful of
  ratings the ordering is honest but thin — the community-building work feeds
  this directly.
- **The catalogue seed is the current bottleneck, not the UI.** As of this
  research: 1,405 works, of which **1** carries a genre and **3** a form
  (the OpenLibrary bulk seed didn't map them), while languages are
  well-populated. The genre/form chip rows hide when empty, so the UI degrades
  cleanly — but enriching genre/form (and page counts, for the length filter)
  in the ETL is what makes these filters sing. Tracked as follow-up work.

## Sources

- [Glimpse — Books & publishing trends 2026](https://meetglimpse.com/trends/books-publishing-trends/)
- [Automateed — Book topics search trends 2026](https://www.automateed.com/book-topics)
- [Accio — Latest Malayalam novels 2026 trend](https://www.accio.com/business/latest-malayalam-novels-2026-trend)
- [Accio — Book sales by genre 2026](https://www.accio.com/business/book-sales-by-genre-trend)
- [Mayfair — Book trends 2026 (shorter reads)](https://mayfairpublishers.com/book-trends/)
- [Headway — Short books under 200 pages](https://makeheadway.com/blog/short-books-to-read/)
- [BookBrowse read-alikes](https://www.bookbrowse.com/read-alikes/)
- [Storizen — Best books to read 2026 India](https://storizen.com/books/best-books-to-read-2026-india/)

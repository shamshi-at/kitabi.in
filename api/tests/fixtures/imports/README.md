# Import fixtures

Read by `tests/test_import_formats.py`. **The header row of every file is a real
export's header row, copied byte for byte**; the data rows are Kitabi books
written in that export's own cell format. Don't retype a header from memory —
the first attempt here did, and got Goodreads' last two columns wrong.

| File | Header copied from | What the rows reproduce |
|---|---|---|
| `libib_export.csv` | A Libib export dated 13 Oct 2026 (`library_20261013_163504.csv` in github.com/kaanyaren/cklibrary) — the newest shape, with a leading `id` | Strings quoted, numbers bare; `status` written with a leading space (`" Not begun"`, `" In progress"`, `" Completed"`, `" Abandoned"`), and `began`/`completed` as `" "` when unset — as in github.com/bcanata/notlar.im `src/data/library.csv` |
| `libib_export_2025.csv` | A Libib export of items added 22 Aug 2025 (github.com/roundlycat/Meridian `hardware/data/library.csv`); the same header as an export of 10 Apr 2026 (github.com/hedlesschkn/Equipment-Manager `library_20260410_051344.csv`) | The older shape, without `id` |
| `librarything_export.csv` | LibraryThing's comma-separated export (github.com/robdmc/libraryThing `LibraryThing_export.csv`, 2014–17) | `Primary Author` surname first; `ISBN` as `[8126403454]`, `ISBNs` as `"[…, …]"`; dates bare |
| `librarything_export.tsv` | LibraryThing's tab-delimited export of 4 Sep 2026 (github.com/devangel77b/pllup `librarything_devangel77b_202609041716.tsv`) — five more columns than the CSV | Dates bracketed (`[2024-03-10]`), an empty ISBN as `[]`, `ISBNs` unbracketed — as in that file, BookWyrm's `bookwyrm/tests/data/librarything.tsv` and github.com/TurtleEngr/libre-bib-old `src/doc/example/librarything.tsv` |
| `goodreads_export.csv` | Goodreads' export (BookWyrm's `bookwyrm/tests/data/goodreads.csv`) | ISBNs armoured as `="…"`, dates as `2024/03/10` |

Two facts the docs gave rather than a file: Libib's support page lists the four
statuses and says `rating` allows half stars ("4.5"); its *import* template
(`began_date`, `completed_date`, `review_created`) is not its *export* shape
(`began`, `completed`, `review_date`) — the export is what readers bring.

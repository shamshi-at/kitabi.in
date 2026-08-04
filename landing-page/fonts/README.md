# Self-hosted fonts

Fraunces (display/serif) and Inter (UI/sans), the two brand faces from
[docs/screen-design.md](../../docs/screen-design.md), served from our own origin.

## Why self-hosted rather than Google Fonts

A `<link>` to `fonts.googleapis.com` costs a DNS lookup, a TLS handshake, a CSS
round trip and *then* a font fetch from a second origin (`fonts.gstatic.com`) —
all before a glyph paints. That was one of the measured problems with the old
pages, and the performance budget allows **zero third-party origins**
([web-platform-plan.md](../../docs/web-platform-plan.md) §6). Self-hosted, these
are same-origin, cached for a year, and covered by the site's own headers.

It is also a privacy improvement: no third party sees a request for every page
view.

## What's here

| File | Subset | Size |
|---|---|---|
| `fraunces-latin.woff2` | `latin` | 66 KB |
| `fraunces-latin-ext.woff2` | `latin-ext` | 58 KB |
| `inter-latin.woff2` | `latin` | 47 KB |
| `inter-latin-ext.woff2` | `latin-ext` | 83 KB |

Both are **variable** fonts (weight axis), so one file covers every weight the
site uses — which is why they're larger than a single static cut and still
cheaper than shipping four of them.

`latin-ext` is declared with a `unicode-range`, so a page only downloads it if it
actually renders one of those characters. That matters more here than on a
typical site: this catalogue is full of transliterated names — *Bibhūtibhūshaṇa*,
*Ḥāfiẓ*, *Kāśīnātha*, *Humāẏūna* — and without the extended subset the browser
falls back per-glyph and the name renders in two different typefaces.

## Indic scripts are NOT self-hosted, deliberately

The plan originally called for bundling Noto Sans Malayalam. We didn't, for two
reasons:

1. The catalogue spans **14 Indic languages**, not one. Shipping Malayalam alone
   would be arbitrary; shipping all fourteen is ~500 KB of fonts to solve a
   problem that mostly isn't there.
2. Every current platform — macOS, iOS, Android, Windows — ships Indic system
   fonts, and the native-script titles render correctly today (verified on the
   deployed language hubs).

So Indic text uses the system stack. If a specific script turns out to render
badly on a platform readers actually use, add that one family with its own
`unicode-range` — the CSS is already structured for it.

## Licences

Both are **SIL Open Font License 1.1**, which explicitly permits redistribution
and self-hosting. Full text: [`OFL.txt`](OFL.txt).

- Fraunces — Undercase Type (Phaedra Charles, Flavia Zimbardi)
- Inter — Rasmus Andersson

## Updating

Fetch the current subset URLs from the Google Fonts CSS API and re-download:

```bash
curl -s -A "Mozilla/5.0 Chrome/120" \
  "https://fonts.googleapis.com/css2?family=Fraunces:opsz,wght@9..144,400..700&display=swap"
```

The `@font-face` blocks live in `functions/_lib/css.js`, not here — they are
inlined into every page along with the rest of the stylesheet. If the file names
change, update them there too.

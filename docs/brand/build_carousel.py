#!/usr/bin/env python3
"""Build the Kitabi Instagram intro carousel — 7 × 1080px slides.

Renders one SVG per slide in the Reading Room palette, then rasterises via
qlmanage (the only SVG renderer available on this machine; see CLAUDE.md).

Type note: the design tokens call for Fraunces, which is not installed and not
vendored in the repo. Georgia is the stand-in — ships with macOS, same literary
serif register. Install Fraunces and change SERIF below to switch.

Usage:  python3 build_carousel.py   (from docs/brand/)
"""

import subprocess
from pathlib import Path

HERE = Path(__file__).parent
OUT = HERE / "carousel"

PAPER, CARD, INK, INK_SOFT = "#F6F0E3", "#FFFCF4", "#2B2118", "#7A6A55"
LINE, OXBLOOD, OXDEEP = "#E2D6BD", "#7E2A33", "#5E1F26"
GOLD, GOLD_SOFT, CREAM = "#B8862B", "#F0E2C2", "#F6F0E3"
RIBBON, PAGELINE = "#C9973B", "#D9CBAA"

SERIF = "Georgia, 'Times New Roman', serif"

W = 1080
M = 108  # side margin


def esc(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def label(text, y, color=GOLD):
    """Small uppercase letter-spaced section label."""
    return (
        f'<text x="{M}" y="{y}" font-family="{SERIF}" font-size="23" fill="{color}" '
        f'letter-spacing="4.5" font-weight="bold">{esc(text.upper())}</text>'
    )


def lines(rows, y, size, color, lh, weight="normal", style="normal", x=M):
    """Manually wrapped text block — SVG has no auto-wrap."""
    out = []
    for i, r in enumerate(rows):
        out.append(
            f'<text x="{x}" y="{y + i * lh}" font-family="{SERIF}" font-size="{size}" '
            f'fill="{color}" font-weight="{weight}" font-style="{style}">{esc(r)}</text>'
        )
    return "\n  ".join(out)


def rule(y, color=LINE, w=3, x=M, length=180):
    return f'<rect x="{x}" y="{y}" width="{length}" height="{w}" fill="{color}"/>'


def frame(bg, inset=GOLD, op=".45"):
    """Full-bleed background + gold hairline inset, the brand's signature."""
    return (
        f'<rect width="{W}" height="{W}" fill="{bg}"/>'
        f'<rect x="34" y="34" width="{W-68}" height="{W-68}" rx="10" fill="none" '
        f'stroke="{inset}" stroke-width="3" opacity="{op}"/>'
    )


def book(cx, cy, scale):
    """The Gold Line mark, from app_icon.svg, re-centred and scaled."""
    return f'''<g transform="translate({cx},{cy}) scale({scale}) translate(-512,-564)">
    <path d="M228 320 C328 272 436 272 500 312 L500 732 C436 696 328 696 228 740 Z" fill="{CREAM}"/>
    <path d="M796 320 C696 272 588 272 524 312 L524 732 C588 696 696 696 796 740 Z" fill="{CREAM}"/>
    <rect x="500" y="296" width="24" height="444" rx="12" fill="{OXDEEP}"/>
    <g stroke="{PAGELINE}" stroke-width="18" stroke-linecap="round">
      <path d="M300 428 H428"/><path d="M300 504 H428"/><path d="M300 580 H392"/>
      <path d="M596 428 H724"/><path d="M632 580 H724"/>
    </g>
    <path d="M596 504 H724" stroke="{GOLD}" stroke-width="20" stroke-linecap="round"/>
    <path d="M480 712 L544 712 L544 856 L512 820 L480 856 Z" fill="{RIBBON}"/>
  </g>'''


def page(n, total, dark=False):
    """Slide counter, bottom right."""
    c = GOLD if dark else INK_SOFT
    return (
        f'<text x="{W-M}" y="{W-72}" text-anchor="end" font-family="{SERIF}" '
        f'font-size="24" fill="{c}" letter-spacing="2">{n} / {total}</text>'
    )


def wordmark(dark=False):
    c = GOLD if dark else OXBLOOD
    return (
        f'<text x="{M}" y="{W-72}" font-family="{SERIF}" font-size="24" fill="{c}" '
        f'letter-spacing="5" font-weight="bold">KITABI</text>'
    )


SLIDES = []

# 1 — the hook
SLIDES.append(f"""{frame(OXBLOOD)}
  {lines(["I lent three books.", "I don't remember", "to whom."], 450, 96, CREAM, 122, "bold")}
  {rule(820, GOLD, 5, M, 160)}
  {wordmark(True)}""")

# 2 — the idea
SLIDES.append(f"""{frame(PAPER, GOLD, ".35")}
  {lines(["Other apps track", "what you read."], 400, 76, INK_SOFT, 100)}
  {lines(["Kitabi tracks", "what you own."], 640, 86, OXBLOOD, 108, "bold")}
  {rule(800, GOLD, 6, M, 260)}
  {wordmark()}""")

# 3 — lending
SLIDES.append(f"""{frame(PAPER, GOLD, ".35")}
  {lines(["Every book", "you lent,", "remembered."], 380, 88, INK, 112, "bold")}
  <rect x="{M}" y="740" width="300" height="80" rx="40" fill="{GOLD_SOFT}"/>
  <text x="{M+44}" y="792" font-family="{SERIF}" font-size="36" fill="#8F681E" font-weight="bold">Free. Always.</text>
  {wordmark()}""")

# 4 — language
SLIDES.append(f"""{frame("#3A2C1E", GOLD, ".4")}
  {lines(["Malayalam.", "Hindi. Tamil.", "Your language,", "first-class."], 360, 82, CREAM, 108, "bold")}
  {rule(840, GOLD, 5, M, 160)}
  {wordmark(True)}""")

# 5 — the close
SLIDES.append(f"""{frame(OXBLOOD)}
  {book(540, 400, 0.50)}
  <text x="540" y="684" text-anchor="middle" font-family="{SERIF}" font-size="82" fill="{CREAM}" font-weight="bold" letter-spacing="3">Kitabi</text>
  <text x="540" y="752" text-anchor="middle" font-family="{SERIF}" font-size="38" fill="{GOLD}" font-style="italic">Beyond the Bookshelf</text>
  <text x="540" y="880" text-anchor="middle" font-family="{SERIF}" font-size="40" fill="{CREAM}" font-weight="bold" letter-spacing="2">kitabi.in</text>""")


def main():
    OUT.mkdir(exist_ok=True)
    for old in OUT.glob("*"):
        old.unlink()

    paths = []
    for i, body in enumerate(SLIDES, 1):
        p = OUT / f"slide-{i}.svg"
        p.write_text(
            f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {W}" '
            f'width="{W}" height="{W}">\n  {body}\n</svg>\n'
        )
        paths.append(p)

    subprocess.run(
        ["qlmanage", "-t", "-s", str(W), "-o", str(OUT), *[str(p) for p in paths]],
        capture_output=True,
    )
    for i in range(1, len(SLIDES) + 1):
        src = OUT / f"slide-{i}.svg.png"
        if src.exists():
            src.rename(OUT / f"kitabi-carousel-{i}.png")
    print(f"built {len(list(OUT.glob('*.png')))} PNGs in {OUT}")


if __name__ == "__main__":
    main()

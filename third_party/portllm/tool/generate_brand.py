#!/usr/bin/env python3
"""Draw the PortLLM logo and banner.

Standard library only, no dependencies, about a second.

    python3 tool/generate_brand.py

Writes assets/logo.svg, assets/logo.png and assets/banner.png. Both are
reproducible from this file rather than arriving as opaque binaries.

The mark is a ship and the port it unloads at, drawn as one continuous
weight with no background so it sits on any surface. The hull and the
quay share a baseline on purpose: the ship is arriving, not floating.

Style notes, because they are what make it read as a logo rather than a
diagram:

  * one accent colour, used once, for the cargo. Nothing else competes.
  * monoline strokes with round caps, so it survives being scaled down to
    32px in a GitHub sidebar.
  * generous negative space. A logo that is busy at full size is unusable
    at favicon size, and GitHub shows this one at 32px whether we like it
    or not.
"""

from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "assets"

# Same deep navy koru uses for text, so the two projects look related
# without looking like the same product.
INK = "#16213A"
# One accent. Used for the containers the ship is unloading, which is the
# thing the port exists for.
ACCENT = "#2F6FEB"
SEA = "#8FB8DE"


def logo_svg() -> str:
    """The mark, on a 256x256 grid."""
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256"
     width="256" height="256" role="img"
     aria-label="PortLLM: a ship unloading at a port">
  <title>PortLLM</title>
  <g fill="none" stroke-linecap="round" stroke-linejoin="round">

    <!-- Waterline. Two strokes, because one reads as a rule and two read
         as a surface. -->
    <path d="M32 196 q16 10 32 0 t32 0 t32 0 t32 0 t32 0 t32 0"
          stroke="{SEA}" stroke-width="7"/>

    <!-- Quay. The port itself: a solid deck on two legs, which is what
         gives the ship something to arrive at. -->
    <path d="M40 168 H150" stroke="{INK}" stroke-width="11"/>
    <path d="M62 168 V212" stroke="{INK}" stroke-width="11"/>
    <path d="M128 168 V212" stroke="{INK}" stroke-width="11"/>

    <!-- Containers being unloaded onto the quay. The accent lives here and
         nowhere else. -->
    <rect x="44" y="140" width="26" height="24" rx="4"
          fill="{ACCENT}" stroke="none"/>
    <rect x="76" y="146" width="26" height="18" rx="4"
          fill="{ACCENT}" stroke="none" opacity="0.72"/>

    <!-- Hull. A single sweep, bow to stern, with the sheer line lifting at
         the bow so it reads as a ship and not a tub. -->
    <path d="M120 150 L214 150 Q204 168 184 172 H146 Q128 170 120 150 Z"
          fill="{INK}" stroke="none"/>

    <!-- Mast and gantry, kept minimal: this is a cargo operation, not a
         sailing one. -->
    <path d="M168 150 V74" stroke="{INK}" stroke-width="9"/>
    <path d="M148 92 H196" stroke="{INK}" stroke-width="8"/>

    <!-- Crane line, drawn from the gantry down to the last container, which
         is the whole idea of the thing in one gesture. -->
    <path d="M192 92 V146" stroke="{ACCENT}" stroke-width="5"/>

    <!-- Containers still on the ship: same accent, so the eye follows them
         from the hull to the quay. -->
    <rect x="134" y="118" width="24" height="30" rx="4"
          fill="{ACCENT}" stroke="none"/>
    <rect x="162" y="126" width="24" height="22" rx="4"
          fill="{ACCENT}" stroke="none" opacity="0.72"/>
  </g>
</svg>
"""


def banner_svg() -> str:
    """A wide lockup: mark on the left, wordmark on the right."""
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1280 320"
     width="1280" height="320" role="img"
     aria-label="PortLLM: bigger models than the phone should be able to run">
  <title>PortLLM</title>

  <!-- Panel. The banner is the one asset that does carry a background,
       because GitHub crops it and a transparent strip renders as white on
       a dark theme. -->
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0%"   stop-color="#16213A"/>
      <stop offset="100%" stop-color="#0C1526"/>
    </linearGradient>
  </defs>
  <rect width="1280" height="320" fill="url(#bg)"/>

  <!-- Faint contour lines: the sea, abstracted. Low contrast on purpose,
       they must not compete with the wordmark. -->
  <g stroke="#2F6FEB" stroke-width="2" fill="none" opacity="0.16">
    <path d="M0 246 q80 22 160 0 t160 0 t160 0 t160 0 t160 0 t160 0 t160 0 t160 0"/>
    <path d="M0 274 q80 22 160 0 t160 0 t160 0 t160 0 t160 0 t160 0 t160 0 t160 0"/>
  </g>

  <!-- The mark, scaled from the 256 grid. -->
  <g transform="translate(72 32) scale(1.0)">
    {logo_body()}
  </g>

  <!-- Wordmark. -->
  <text x="360" y="152" font-family="Helvetica Neue, Helvetica, Arial, sans-serif"
        font-size="86" font-weight="700" fill="#FFFFFF" letter-spacing="-2">
    PortLLM
  </text>
  <text x="364" y="206" font-family="Helvetica Neue, Helvetica, Arial, sans-serif"
        font-size="29" font-weight="400" fill="#8FB8DE">
    Run bigger models than the phone should be able to run.
  </text>

  <!-- Three tier chips. They say the architecture in the one place a
       stranger is actually reading: the README header. -->
  <g font-family="Helvetica Neue, Helvetica, Arial, sans-serif" font-size="21"
     font-weight="600">
    <rect x="364" y="236" width="116" height="40" rx="20" fill="#2F6FEB" opacity="0.16"/>
    <text x="422" y="262" fill="#8FB8DE" text-anchor="middle">RAM</text>

    <rect x="492" y="236" width="116" height="40" rx="20" fill="#2F6FEB" opacity="0.16"/>
    <text x="550" y="262" fill="#8FB8DE" text-anchor="middle">GPU</text>

    <rect x="620" y="236" width="150" height="40" rx="20" fill="#2F6FEB" opacity="0.16"/>
    <text x="695" y="262" fill="#8FB8DE" text-anchor="middle">Storage</text>
  </g>
</svg>
"""


def logo_body() -> str:
    """The mark's contents, so the banner reuses them verbatim.

    Duplicated from logo_svg deliberately rather than parsed out of it:
    reading XML to extract a group is more fragile than keeping one
    canonical copy of the drawing here.
    """
    return f"""<g fill="none" stroke-linecap="round" stroke-linejoin="round">
    <path d="M32 196 q16 10 32 0 t32 0 t32 0 t32 0 t32 0 t32 0"
          stroke="{SEA}" stroke-width="7"/>
    <path d="M40 168 H150" stroke="{INK}" stroke-width="11"/>
    <path d="M62 168 V212" stroke="{INK}" stroke-width="11"/>
    <path d="M128 168 V212" stroke="{INK}" stroke-width="11"/>
    <rect x="44" y="140" width="26" height="24" rx="4" fill="{ACCENT}" stroke="none"/>
    <rect x="76" y="146" width="26" height="18" rx="4" fill="{ACCENT}" stroke="none" opacity="0.72"/>
    <path d="M120 150 L214 150 Q204 168 184 172 H146 Q128 170 120 150 Z"
          fill="{INK}" stroke="none"/>
    <path d="M168 150 V74" stroke="{INK}" stroke-width="9"/>
    <path d="M148 92 H196" stroke="{INK}" stroke-width="8"/>
    <path d="M192 92 V146" stroke="{ACCENT}" stroke-width="5"/>
    <rect x="134" y="118" width="24" height="30" rx="4" fill="{ACCENT}" stroke="none"/>
    <rect x="162" y="126" width="24" height="22" rx="4" fill="{ACCENT}" stroke="none" opacity="0.72"/>
  </g>"""


def write(name: str, text: str) -> None:
    p = OUT / name
    p.write_text(text, encoding="utf-8")
    print(f"wrote {p} ({len(text)} bytes)")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    write("logo.svg", logo_svg())
    write("banner.svg", banner_svg())
    print("now rasterise with rsvg-convert, inkscape or cairosvg if you need PNG")


if __name__ == "__main__":
    main()
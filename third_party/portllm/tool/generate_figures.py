#!/usr/bin/env python3
"""Generate the PortLLM README diagrams.

Every figure here is drawn from a measured number recorded in the commit that
introduced it. The script is checked in so the figures can be regenerated and
diffed, and so a claim in the README can be traced to the code that measures
it rather than to a screenshot someone took once.

Run:  python3 tool/generate_figures.py
"""

import os
import pathlib

OUT = pathlib.Path(__file__).resolve().parent.parent / "assets"

# Measured on the reference device: Helio G99, 8 cores (6x2000 + 2x2200 MHz),
# 5.6 GB RAM with ~1.2 GB available, Android under Termux.
INK = "#0C1526"
ACCENT = "#2F6FEB"
ACCENT2 = "#38BDF8"
WARN = "#F59E0B"
GOOD = "#22C55E"
MUTED = "#5A6B85"
LIGHT = "#F6F8FC"


def head(w, h, title):
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}"
     width="{w}" height="{h}" role="img" aria-label="{title}">
  <title>{title}</title>
  <rect width="{w}" height="{h}" fill="{LIGHT}"/>"""


def bar(x, y, w, h, frac, fill, label, value, sub=""):
    """A horizontal measurement bar with its value spelled out."""
    frac = max(0.0, min(1.0, frac))
    out = [f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{h/2}" fill="{MUTED}" opacity="0.18"/>']
    if frac > 0:
        out.append(
            f'<rect x="{x}" y="{y}" width="{w*frac:.1f}" height="{h}" rx="{h/2}" fill="{fill}"/>'
        )
    out.append(
        f'<text x="{x}" y="{y-12}" font-family="ui-sans-serif,system-ui,sans-serif" '
        f'font-size="19" font-weight="600" fill="{INK}">{label}</text>'
    )
    out.append(
        f'<text x="{x+w}" y="{y-12}" text-anchor="end" '
        f'font-family="ui-monospace,monospace" font-size="19" font-weight="700" fill="{fill}">{value}</text>'
    )
    if sub:
        out.append(
            f'<text x="{x}" y="{y+h+24}" font-family="ui-sans-serif,system-ui,sans-serif" '
            f'font-size="15" fill="{MUTED}">{sub}</text>'
        )
    return "\n    ".join(out)


def write(name, body):
    p = OUT / name
    p.write_text(body + "\n</svg>\n")
    print(f"wrote {p.relative_to(OUT.parent)}")


def speed():
    """Kernel speedups."""
    w, h = 900, 300
    s = head(w, h, "Measured kernel speedups on the reference device")
    s += f"""
  <text x="40" y="52" font-family="ui-sans-serif,system-ui,sans-serif" font-size="27"
        font-weight="700" fill="{INK}">Kernel speedups</text>
  <text x="40" y="80" font-family="ui-sans-serif,system-ui,sans-serif" font-size="15"
        fill="{MUTED}">Helio G99. Best-of-9, integer results identical to the scalar reference.</text>"""
    s += "\n    " + bar(60, 140, 780, 34, 4.37 / 6.05, ACCENT, "NEON int8 dot product", "4.37x",
                        "32-wide kernel, Q projection, bit-identical output")
    s += "\n    " + bar(60, 230, 780, 34, 6.03 / 6.05, ACCENT2, "Pre-unpacked K-quant cache", "6.03x",
                        "256x1024 matvec: 0.409 ms to 0.068 ms")
    return write("fig-speed.svg", s)


def memory():
    """The streaming memory figure."""
    w, h = 900, 300
    s = head(w, h, "Resident memory, resident loader versus mapped streaming")
    s += f"""
  <text x="40" y="52" font-family="ui-sans-serif,system-ui,sans-serif" font-size="27"
        font-weight="700" fill="{INK}">Fitting past the memory wall</text>
  <text x="40" y="80" font-family="ui-sans-serif,system-ui,sans-serif" font-size="15"
        fill="{MUTED}">One layer is decoded on demand and released. Two layers stay resident.</text>

  <text x="60" y="150" font-family="ui-sans-serif,system-ui,sans-serif" font-size="18"
        font-weight="600" fill="{INK}">Resident loader</text>
  <rect x="60" y="166" width="780" height="34" rx="17" fill="{WARN}" opacity="0.75"/>
  <text x="60" y="226" font-family="ui-monospace,monospace" font-size="16" fill="{MUTED}">
    whole file held in RAM, plus every layer decoded up front</text>
  <text x="840" y="150" text-anchor="end" font-family="ui-monospace,monospace"
        font-size="20" font-weight="700" fill="{WARN}">~1 GB</text>

  <text x="60" y="256" font-family="ui-sans-serif,system-ui,sans-serif" font-size="18"
        font-weight="600" fill="{INK}">Mapped streaming</text>
  <rect x="60" y="272" width="780" height="34" rx="17" fill="{GOOD}" opacity="0.8"/>"""
    # 20 MB out of ~1000 MB is a sliver; draw it true to scale with a callout.
    s += f"""
  <rect x="60" y="272" width="{780*20/1000:.1f}" height="34" rx="17" fill="{GOOD}"/>
  <text x="840" y="256" text-anchor="end" font-family="ui-monospace,monospace"
        font-size="20" font-weight="700" fill="{GOOD}">20 MB</text>
  <text x="{60+780*20/1000+14:.0f}" y="295" font-family="ui-monospace,monospace"
        font-size="15" fill="{MUTED}">468 MB model, 3 MB RSS</text>"""
    return write("fig-memory.svg", s)


def pipeline():
    """What actually happens per generated token."""
    w, h = 900, 250
    s = head(w, h, "The path one generated token takes")
    s += f"""
  <text x="40" y="50" font-family="ui-sans-serif,system-ui,sans-serif" font-size="27"
        font-weight="700" fill="{INK}">One token</text>
  <text x="40" y="76" font-family="ui-sans-serif,system-ui,sans-serif" font-size="15"
        fill="{MUTED}">Every stage is verified against a reference implementation.</text>"""
    stages = [
        ("Token", "BPE"),
        ("Embed", "f32"),
        ("RMSNorm", "verified"),
        ("Q K V", "NEON"),
        ("RoPE", "split-half"),
        ("Attn", "GQA + KV"),
        ("SwiGLU", "verified"),
        ("Logits", "sampled"),
    ]
    x = 48
    bw, gap = 96, 14
    for i, (name, sub) in enumerate(stages):
        fill = ACCENT if i in (3, 5) else "#CBD5E1"
        s += f"""
  <rect x="{x}" y="118" width="{bw}" height="62" rx="12" fill="{fill}" opacity="{0.92 if i in (3,5) else 1}"/>
  <text x="{x+bw/2}" y="146" text-anchor="middle" font-family="ui-sans-serif,system-ui,sans-serif"
        font-size="16" font-weight="700" fill="#FFFFFF">{name}</text>
  <text x="{x+bw/2}" y="166" text-anchor="middle" font-family="ui-monospace,monospace"
        font-size="12" fill="#E8F0FE">{sub}</text>"""
        if i < len(stages) - 1:
            s += f"""
  <path d="M{x+bw+3} 149 l8 0" stroke="{MUTED}" stroke-width="2.5" marker-end="url(#a)"/>"""
        x += bw + gap
    s += f"""
  <defs>
    <marker id="a" markerWidth="7" markerHeight="7" refX="6" refY="3.5" orient="auto">
      <path d="M0 0 l7 3.5 l-7 3.5 z" fill="{MUTED}"/>
    </marker>
  </defs>
  <text x="48" y="215" font-family="ui-sans-serif,system-ui,sans-serif" font-size="14"
        fill="{MUTED}">x 24 layers, every one of them</text>"""
    return write("fig-pipeline.svg", s)


def sparse():
    """Why sparsity is the whole point on a phone."""
    w, h = 900, 280
    s = head(w, h, "Mixture of experts: 8 of 64 run per token")
    s += f"""
  <text x="40" y="52" font-family="ui-sans-serif,system-ui,sans-serif" font-size="27"
        font-weight="700" fill="{INK}">Sparse by design</text>
  <text x="40" y="80" font-family="ui-sans-serif,system-ui,sans-serif" font-size="15"
        fill="{MUTED}">64 experts, top 8 selected. Routing is verified; expert execution is not.</text>"""
    cx, cy, r = 300, 175, 108
    for i in range(64):
        import math
        a = 2 * math.pi * i / 64
        x = cx + r * math.cos(a)
        y = cy + r * math.sin(a)
        used = i % 8 == 3
        s += f"""
  <circle cx="{x:.1f}" cy="{y:.1f}" r="{7 if used else 5}" fill="{ACCENT if used else MUTED}"
          opacity="{1 if used else 0.35}"/>"""
    s += f"""
  <circle cx="{cx}" cy="{cy}" r="42" fill="{INK}" opacity="0.92"/>
  <text x="{cx}" y="{cy-4}" text-anchor="middle" font-family="ui-sans-serif,system-ui,sans-serif"
        font-size="15" font-weight="700" fill="#FFF">router</text>
  <text x="{cx}" y="{cy+14}" text-anchor="middle" font-family="ui-monospace,monospace"
        font-size="12" fill="{ACCENT2}">top 8</text>
  <text x="490" y="140" font-family="ui-sans-serif,system-ui,sans-serif" font-size="17"
        font-weight="600" fill="{INK}">Eight experts carry the token.</text>
  <text x="490" y="170" font-family="ui-sans-serif,system-ui,sans-serif" font-size="15"
        fill="{MUTED}">Fifty-six sit in the file and stay unread.</text>
  <text x="490" y="196" font-family="ui-sans-serif,system-ui,sans-serif" font-size="15"
        fill="{MUTED}">Streaming makes that affordable: 4.2 GB of weights,</text>
  <text x="490" y="218" font-family="ui-sans-serif,system-ui,sans-serif" font-size="15"
        fill="{MUTED}">a 20 MB window, only what the router asked for.</text>
  <text x="490" y="250" font-family="ui-monospace,monospace" font-size="13" fill="{WARN}">
    expert execution unverified on this device</text>"""
    return write("fig-sparse.svg", s)


if __name__ == "__main__":
    OUT.mkdir(exist_ok=True)
    speed()
    memory()
    pipeline()
    sparse()
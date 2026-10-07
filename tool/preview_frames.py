#!/usr/bin/env python3
"""Contact sheet for eyeballing individual mascot frames.

    python3 tool/preview_frames.py

Writes a single PNG with one labelled cell per frame, on a checkerboard so the
cell boundaries and the anti-aliasing are both visible. This is a review aid,
not a shipped asset.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import generate_assets as G  # noqa: E402

CELL = G.CELL
SCALE = 2
PAD = 8
LABEL = 22


def cell_background(w, h, shade):
    base = (0xEE if shade else 0xF6, 0xEE if shade else 0xF6, 0xEE if shade else 0xF6)
    r = G.Raster(w, h)
    step = 12
    for y in range(0, h, step):
        for x in range(0, w, step):
            if ((x // step) + (y // step)) % 2 == 0:
                r.fill_rect(x, y, x + step, y + step, base)
    return r


def main():
    clips = sys.argv[1:] or [name for name, _ in G.CLIPS]
    wanted = []
    for clip in clips:
        total = G.CLIPS[dict(G.CLIPS)[clip]][1] if False else None
    for clip in clips:
        total = dict(G.CLIPS)[clip]
        for f in range(total):
            wanted.append((clip, f))

    cell_w = CELL * SCALE
    cell_h = CELL * SCALE
    cols = min(8, len(wanted))
    rows = (len(wanted) + cols - 1) // cols
    width = cols * (cell_w + PAD) + PAD
    height = rows * (cell_h + PAD + LABEL) + PAD

    sheet = G.Raster(width, height)
    sheet.fill_rect(0, 0, width, height, (0x33, 0x33, 0x33))

    for i, (clip, f) in enumerate(wanted):
        col, row = i % cols, i // cols
        x = PAD + col * (cell_w + PAD)
        y = PAD + row * (cell_h + PAD + LABEL)
        bg = cell_background(cell_w, cell_h, (col + row) % 2 == 0)
        frame = G.render_pose(G.pose_for(clip, f, dict(G.CLIPS)[clip]))
        frame = frame.downsample(max(1, frame.w // cell_w))
        bg.blit(frame, (cell_w - frame.w) // 2, (cell_h - frame.h) // 2)
        sheet.blit(bg, x, y)

    out = "/tmp/koru_preview.png"
    data = G.encode_png(sheet)
    with open(out, "wb") as fh:
        fh.write(data)
    order = " ".join("%s%d" % (c[:3], f) for c, f in wanted)
    print("%s  %dx%d" % (out, sheet.w, sheet.h))
    print("order (left to right, top to bottom):")
    print("  " + order)


if __name__ == "__main__":
    main()

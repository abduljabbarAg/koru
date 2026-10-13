#!/usr/bin/env python3
"""Renders mascot candidates as ASCII so they can be judged before any asset is
regenerated.

    python3 tool/preview_chars.py [candidate ...]

Regenerating the real atlas takes minutes, and a beard drawn blind is exactly
how the last one went wrong. This draws one frame per candidate in about a
second and prints it, so the shape can be looked at rather than assumed.
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import generate_assets as G  # noqa: E402

# Coarse palette so the character reads at a glance in a terminal.
SHADES = " .:-=+*#%@"


def to_ascii(ras, cols=72, rows=36):
    """Downsamples RGBA to text.

    Pure luminance turned the character into mud: the leaf outline, the cream
    shell and the ink features are all mid-grey. Classifying by hue instead
    separates the things a designer actually looks at, so the silhouette, the
    outline and the face read as different marks.

      space  empty, or the cream shell itself
      +      the leaf green outline
      #      ink: eyes, mouth, spectacles, beard
      .      clay: blush
      :      the faint contact shadow
    """
    img, w, h = ras.px, ras.w, ras.h
    out = []
    for ry in range(rows):
        line = []
        for rx in range(cols):
            x0, x1 = max(1, int(rx * w / cols)), max(2, int((rx + 1) * w / cols))
            y0, y1 = max(1, int(ry * h / rows)), max(2, int((ry + 1) * h / rows))
            rsum = gsum = bsum = asum = 0.0
            n = 0
            for y in range(y0, min(y1, h)):
                base = y * w * 4
                for x in range(x0, min(x1, w)):
                    o = base + x * 4
                    a = img[o + 3] / 255.0
                    if a < 0.05:
                        continue
                    rsum += img[o] * a
                    gsum += img[o + 1] * a
                    bsum += img[o + 2] * a
                    asum += a
                    n += 1
            if n == 0:
                line.append(" ")
                continue
            r, g, b = rsum / asum, gsum / asum, bsum / asum
            lum = (r + g + b) / 3
            cov = asum / ((x1 - x0) * (y1 - y0))
            if lum > 240:
                line.append(" ")
            elif lum < 110:
                line.append("#" if cov > 0.3 else ":")
            elif g > r + 12 and g > b + 12:
                line.append("+" if cov > 0.3 else ",")
            elif r > g + 14 and r > b + 14:
                line.append(".")
            else:
                line.append("-" if cov > 0.3 else " ")
        out.append("".join(line))
    return "\n".join(out)


def render(fn, name):
    r = G.Raster(G.CELL * G.SS, G.CELL * G.SS)
    pose = G.pose_for("idle", 0, 6)
    fn(r, pose)
    small = r.downsample(G.SS)
    return f"\n{'=' * 66}\n{name}\n{'=' * 66}\n" + to_ascii(small)


def main():
    wanted = sys.argv[1:]
    candidates = {name: fn for name, fn in CANDIDATES.items()}
    if not wanted:
        wanted = list(candidates)
    for name in wanted:
        if name not in candidates:
            print(f"unknown candidate {name}; have: {', '.join(candidates)}")
            return 1
        sys.stdout.write(render(candidates[name], name) + "\n")
    return 0


# -- candidates ------------------------------------------------------------

def c_baseline(r, pose, canvas=G.CELL, scale=G.CHAR_SCALE):
    """The 1.2.0 character exactly as it was."""
    G.draw_koru(r, pose)


def c_specs(r, pose, canvas=G.CELL, scale=G.CHAR_SCALE):
    """The same character with only round spectacles. No beard.

    The previous attempt failed because it added a heavy mass to a character
    whose whole appeal is a clean cream shell. One thin pair of rims, drawn as
    an outline, is a detail the silhouette can absorb.
    """
    G.draw_koru(r, pose, canvas=canvas, scale=scale)
    _glasses(r, pose, canvas, scale)


def c_beard_specs(r, pose, canvas=G.CELL, scale=G.CHAR_SCALE):
    """Spectacles plus a beard kept well clear of the mouth."""
    G.draw_koru(r, pose, canvas=canvas, scale=scale)
    _glasses(r, pose, canvas, scale)
    _beard(r, pose, canvas, scale)


def c_goatee(r, pose, canvas=G.CELL, scale=G.CHAR_SCALE):
    """Spectacles plus a small tidy goatee under the mouth."""
    G.draw_koru(r, pose, canvas=canvas, scale=scale)
    _glasses(r, pose, canvas, scale)
    _goatee(r, pose, canvas, scale)


def _geometry(r, pose, canvas=G.CELL, scale=G.CHAR_SCALE):
    s = G.SS * scale * (canvas / float(G.CELL))
    centre = (canvas / 2.0) * G.SS
    body_cx = centre
    body_cy = centre + 22 * s + pose.bob * s
    return s, body_cx, body_cy


def _glasses(r, pose, canvas=G.CELL, scale=G.CHAR_SCALE):
    """Thin rims around the eyes, drawn as strokes so the face shows through."""
    s, cx, cy = _geometry(r, pose, canvas, scale)
    eye_y = cy - 7 * s
    for ex in (cx - 17 * s, cx + 17 * s):
        pts = G.ellipse_pts(ex, eye_y, 12.5 * s, 9.5 * s)
        r.stroke(pts, [1.5 * s] * (len(pts) // 2), G.INK, 0.72)
    # Bridge between the lenses.
    r.stroke_line(cx - 5.0 * s, eye_y - 1.5 * s, cx + 5.0 * s, eye_y - 1.5 * s,
                  1.4 * s, G.INK, 0.72)


def _beard(r, pose, canvas=G.CELL, scale=G.CHAR_SCALE):
    """A jaw beard that sits under the mouth and follows the shell."""
    s, cx, cy = _geometry(r, pose, canvas, scale)
    arc = G.quad(cx - 26 * s, cy + 16 * s, cx, cy + 37 * s, cx + 26 * s, cy + 16 * s)
    r.stroke(arc, [7.0 * s] * (len(arc) // 2), G.INK, 0.13)
    r.stroke(arc, [3.0 * s] * (len(arc) // 2), G.INK, 0.11)


def _goatee(r, pose, canvas=G.CELL, scale=G.CHAR_SCALE):
    """A small patch under the mouth. Reads as a beard without swallowing the
    face, which is the failure mode of the last attempt."""
    s, cx, cy = _geometry(r, pose, canvas, scale)
    mouth_y = cy + 14 * s
    r.ellipse(cx, mouth_y + 11 * s, 8.5 * s, 9.5 * s, G.INK, 0.16)
    r.ellipse(cx, mouth_y + 13 * s, 5.0 * s, 5.5 * s, G.INK, 0.12)


def c_debug(r, pose):
    """Geometry check. The real beard is drawn at alpha 0.13 so it reads as a
    soft shadow; at that strength it also vanishes from the preview, which
    makes it impossible to tell "subtle" from "not drawn at all". This draws the
    same geometry at full strength so the shape can be checked, and nothing
    else."""
    G.draw_koru(r, pose)
    _glasses_hard(r, pose)
    _beard_hard(r, pose)


def _glasses_hard(r, pose):
    s, cx, cy = _geometry(r, pose)
    eye_y = cy - 7 * s
    for ex in (cx - 17 * s, cx + 17 * s):
        pts = G.ellipse_pts(ex, eye_y, 12.5 * s, 9.5 * s)
        r.stroke(pts, [1.5 * s] * (len(pts) // 2), G.INK, 1.0)
    r.stroke_line(cx - 5.0 * s, eye_y - 1.5 * s, cx + 5.0 * s, eye_y - 1.5 * s,
                  1.4 * s, G.INK, 1.0)


def _beard_hard(r, pose):
    s, cx, cy = _geometry(r, pose)
    arc = G.quad(cx - 26 * s, cy + 16 * s, cx, cy + 37 * s, cx + 26 * s, cy + 16 * s)
    r.stroke(arc, [7.0 * s] * (len(arc) // 2), G.INK, 1.0)


CANDIDATES = {
    "baseline": c_baseline,
    "specs": c_specs,
    "beard_specs": c_beard_specs,
    "goatee": c_goatee,
    "debug": c_debug,
}


if __name__ == "__main__":
    raise SystemExit(main())
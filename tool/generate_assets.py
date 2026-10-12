#!/usr/bin/env python3
"""Generates every raster asset Koru ships: the mascot sprite atlas, the splash
illustration and the launcher icons.

    python3 tool/generate_assets.py

Written against the standard library only, on purpose. Assets are build outputs
that happen to live in the repository so a checkout builds with one command, but
every pixel is reproducible from this file rather than arriving as an opaque
binary. Nothing here needs to run in CI: the generated PNGs are committed.

Rendering is a small software rasteriser. Shapes are drawn at 4x and box
filtered down, which is where the anti-aliasing comes from, so there is no
separate coverage pass to get wrong. The atlas layout is mirrored by
lib/mascot/mascot_clips.dart and checked by test/atlas_layout_test.dart.
"""

import math
import os
import struct
import sys
import zlib

# --------------------------------------------------------------------------
# Palette, kept in sync with KoruColors in lib/theme.dart.
# --------------------------------------------------------------------------

INK = (0x14, 0x11, 0x0F)
INK_SOFT = (0x4A, 0x42, 0x3D)
INK_FAINT = (0x8A, 0x7F, 0x78)
CREAM = (0xFB, 0xF8, 0xF4)
LINE = (0xE8, 0xE1, 0xDA)
LEAF = (0x2F, 0x7A, 0x5A)
LEAF_SOFT = (0xE4, 0xF1, 0xEA)
CLAY = (0xC1, 0x66, 0x3F)
LEAF_LITE = (0x4F, 0xA3, 0x7C)

CELL = 192          # logical atlas cell, in pixels
SS = 3              # supersample factor, downsampled to CELL
ATLAS_COLS = 8
ATLAS_ROWS = 4

# Koru is drawn about the cell centre at this scale, sized to leave a little
# breathing room rather than touching the cell edges.
CHAR_SCALE = 1.12

# Clip name -> frame count. Mirrored by kClipFrames in mascot_clips.dart.
CLIPS = [
    ("idle", 6),
    ("blink", 4),
    ("wave", 8),
    ("think", 4),
    ("cheer", 6),
    ("greet", 4),
]


def frames_before(clip):
    n = 0
    for name, count in CLIPS:
        if name == clip:
            return n
        n += count
    raise KeyError(clip)


# --------------------------------------------------------------------------
# RGBA raster with source-over compositing.
# --------------------------------------------------------------------------


class Raster:
    def __init__(self, w, h):
        self.w = w
        self.h = h
        self.px = bytearray(w * h * 4)
        # Dirty rectangle. The mascot fills well under half of its cell, and
        # the downsample pass is the slowest thing in this file, so there is no
        # reason to resample the empty margins.
        self.dirty = [w, h, -1, -1]

    def _touch(self, x_from, x_to, y):
        """Grow the dirty rectangle. Stored as [x_lo, y_lo, x_hi, y_hi]."""
        d = self.dirty
        if x_from < d[0]:
            d[0] = x_from
        if y < d[1]:
            d[1] = y
        if x_to > d[2]:
            d[2] = x_to
        if y > d[3]:
            d[3] = y

    def blend(self, x, y, color, alpha=1.0):
        if x < 0 or y < 0 or x >= self.w or y >= self.h:
            return
        if alpha <= 0:
            return
        i = (y * self.w + x) * 4
        px = self.px
        if alpha >= 1.0:
            r, g, b = color
            px[i] = r
            px[i + 1] = g
            px[i + 2] = b
            px[i + 3] = 255
            return
        da = px[i + 3] / 255.0
        out_a = alpha + da * (1.0 - alpha)
        if out_a <= 0:
            px[i + 3] = 0
            return
        px[i] = min(255, int((color[0] * alpha + px[i] * da * (1 - alpha)) / out_a + 0.5))
        px[i + 1] = min(255, int((color[1] * alpha + px[i + 1] * da * (1 - alpha)) / out_a + 0.5))
        px[i + 2] = min(255, int((color[2] * alpha + px[i + 2] * da * (1 - alpha)) / out_a + 0.5))
        px[i + 3] = min(255, int(out_a * 255 + 0.5))

    def fill_rect(self, x0, y0, x1, y1, color, alpha=1.0):
        x0 = max(0, int(x0))
        y0 = max(0, int(y0))
        x1 = min(self.w, int(x1))
        y1 = min(self.h, int(y1))
        for y in range(y0, y1):
            for x in range(x0, x1):
                self.blend(x, y, color, alpha)

    def _span(self, y, x_from, x_to, color, alpha):
        """Fill one horizontal run. Clipped here so callers stay simple.

        Opaque runs go through a slice assignment instead of a per-pixel call.
        Almost every shape in this file is opaque, and that one change is the
        difference between the generator finishing in seconds and in minutes.
        """
        if y < 0 or y >= self.h:
            return
        x_from = max(0, int(x_from))
        x_to = min(self.w, int(x_to))
        if x_to <= x_from:
            return
        row = y * self.w * 4
        self._touch(x_from, x_to, y)
        if alpha >= 1.0:
            self.px[row + x_from * 4 : row + x_to * 4] = bytes(color + (255,)) * (x_to - x_from)
            return
        for x in range(x_from, x_to):
            self.blend(x, y, color, alpha)

    def ellipse(self, cx, cy, rx, ry, color, alpha=1.0, rot=0.0):
        """Axis aligned ellipse, filled one scanline at a time.

        Solving each row instead of testing every pixel turns the inner loop from
        O(w*h) into O(rows), which is what keeps 32 supersampled frames cheap in
        pure Python. A non-zero rotation falls back to a per pixel test, which is
        fine because only the two hands ever ask for one.
        """
        if rx <= 0 or ry <= 0:
            return
        if rot:
            cos_r, sin_r = math.cos(-rot), math.sin(-rot)
            reach = max(rx, ry)
            for y in range(int(cy - reach) - 1, int(cy + reach) + 2):
                for x in range(int(cx - reach) - 1, int(cx + reach) + 2):
                    dx, dy = x + 0.5 - cx, y + 0.5 - cy
                    lx = dx * cos_r - dy * sin_r
                    ly = dx * sin_r + dy * cos_r
                    if (lx / rx) ** 2 + (ly / ry) ** 2 <= 1.0:
                        self.blend(x, y, color, alpha)
            return
        for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
            dy = (y + 0.5 - cy) / ry
            if dy < -1.0 or dy > 1.0:
                continue
            dx = rx * math.sqrt(max(0.0, 1.0 - dy * dy))
            self._span(y, cx - dx, cx + dx, color, alpha)

    def circle(self, cx, cy, r, color, alpha=1.0):
        self.ellipse(cx, cy, r, r, color, alpha)

    def ellipse_inside(self, cx, cy, rx, ry, inner, color, alpha=1.0):
        """Fill an ellipse but only the part that also falls inside another
        ellipse. Used for belly shading so the tint cannot escape the outline."""
        icx, icy, irx, iry = inner
        for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
            dy = (y + 0.5 - cy) / ry
            if dy < -1.0 or dy > 1.0:
                continue
            dx = rx * math.sqrt(max(0.0, 1.0 - dy * dy))
            idy = (y + 0.5 - icy) / iry
            if idy < -1.0 or idy > 1.0:
                continue
            idx = irx * math.sqrt(max(0.0, 1.0 - idy * idy))
            lo = max(cx - dx, icx - idx)
            hi = min(cx + dx, icx + idx)
            self._span(y, lo, hi, color, alpha)

    def polygon(self, pts, color, alpha=1.0):
        """Even-odd scanline polygon fill. pts is a flat [x0,y0,x1,y1,...]."""
        n = len(pts) // 2
        if n < 3:
            return
        min_y = min(pts[1::2])
        max_y = max(pts[1::2])
        for y in range(int(min_y), int(max_y) + 1):
            sy = y + 0.5
            xs = []
            for i in range(n):
                j = (i + 1) % n
                ay, by = pts[i * 2 + 1], pts[j * 2 + 1]
                if (ay <= sy < by) or (by <= sy < ay):
                    ax, bx = pts[i * 2], pts[j * 2]
                    xs.append(ax + (sy - ay) / (by - ay) * (bx - ax))
            xs.sort()
            for k in range(0, len(xs) - 1, 2):
                self._span(y, xs[k], xs[k + 1], color, alpha)

    def stroke(self, pts, widths, color, alpha=1.0):
        """Variable width stroke.

        `widths` may be one value per point, or just the first and last, in
        which case it is interpolated across the path. The taper is what makes
        the frond read as a frond.
        """
        n = len(pts) // 2
        if n < 2:
            return
        if len(widths) == 2 and n > 2:
            w0, w1 = widths
            widths = [w0 + (w1 - w0) * (i / (n - 1)) for i in range(n)]
        for i in range(n - 1):
            x0, y0 = pts[i * 2], pts[i * 2 + 1]
            x1, y1 = pts[i * 2 + 2], pts[i * 2 + 3]
            w0, w1 = widths[i], widths[i + 1]
            dist = math.hypot(x1 - x0, y1 - y0)
            steps = max(1, int(dist / 1.2) + 1)
            for s in range(steps + 1):
                t = s / steps
                self.circle(
                    x0 + (x1 - x0) * t,
                    y0 + (y1 - y0) * t,
                    (w0 + (w1 - w0) * t) / 2.0,
                    color,
                    alpha,
                )

    def stroke_line(self, x0, y0, x1, y1, width, color, alpha=1.0):
        self.stroke([x0, y0, x1, y1], [width, width], color, alpha)

    def downsample(self, factor):
        """Box filter. Colour is averaged weighted by alpha, otherwise
        transparent pixels bleed dark fringes into every soft edge.

        Two things keep this affordable in pure Python: only the dirty rectangle
        is resampled, and opaque source pixels skip the alpha multiply, which is
        the common case inside the character.
        """
        out = Raster(self.w // factor, self.h // factor)
        px, w = self.px, self.w
        x_lo, y_lo, x_hi, y_hi = self.dirty
        if x_hi < x_lo or y_hi < y_lo:
            return out

        out_lo = max(0, x_lo // factor)
        out_hi = min(out.w, (x_hi + factor - 1) // factor + 1)
        top = max(0, y_lo // factor)
        bottom = min(out.h, (y_hi + factor - 1) // factor + 1)
        count = factor * factor

        for y in range(top, bottom):
            base_y = y * factor
            for x in range(out_lo, out_hi):
                base_x = x * factor
                # Opaque samples are summed raw and counted; translucent ones are
                # accumulated premultiplied. Keeping them apart lets the common
                # case skip a multiply while still averaging correctly, because
                # an opaque sample contributes colour*255 to a premultiplied sum.
                o_r = o_g = o_b = 0.0
                o_n = 0
                t_r = t_g = t_b = t_a = 0.0
                for sy in range(factor):
                    row = (base_y + sy) * w
                    for sx in range(factor):
                        i = (row + base_x + sx) * 4
                        alpha = px[i + 3]
                        if alpha == 255:
                            o_n += 1
                            o_r += px[i]
                            o_g += px[i + 1]
                            o_b += px[i + 2]
                        elif alpha:
                            sa = alpha / 255.0
                            t_a += alpha
                            t_r += px[i] * sa
                            t_g += px[i + 1] * sa
                            t_b += px[i + 2] * sa
                if o_n == count:
                    o = (y * out.w + x) * 4
                    out.px[o] = min(255, int(o_r / count + 0.5))
                    out.px[o + 1] = min(255, int(o_g / count + 0.5))
                    out.px[o + 2] = min(255, int(o_b / count + 0.5))
                    out.px[o + 3] = 255
                    continue
                total_a = o_n * 255.0 + t_a
                if total_a <= 0:
                    continue
                total_r = o_r * 255.0 + t_r
                total_g = o_g * 255.0 + t_g
                total_b = o_b * 255.0 + t_b
                o = (y * out.w + x) * 4
                out.px[o] = min(255, int(total_r / total_a + 0.5))
                out.px[o + 1] = min(255, int(total_g / total_a + 0.5))
                out.px[o + 2] = min(255, int(total_b / total_a + 0.5))
                out.px[o + 3] = min(255, int(total_a / count + 0.5))
        out.dirty = [
            max(0, out_lo - 1),
            max(0, top - 1),
            min(out.w, out_hi + 1),
            min(out.h, bottom + 1),
        ]
        return out

    def blit(self, src, dx, dy):
        d = self.dirty
        for y in range(src.h):
            ty = dy + y
            if ty < 0 or ty >= self.h:
                continue
            row = ty * self.w
            srow = y * src.w
            for x in range(src.w):
                tx = dx + x
                if tx < 0 or tx >= self.w:
                    continue
                i = (srow + x) * 4
                a = src.px[i + 3]
                if a == 0:
                    continue
                if tx < d[0]:
                    d[0] = tx
                if tx > d[2]:
                    d[2] = tx
                if ty < d[1]:
                    d[1] = ty
                if ty > d[3]:
                    d[3] = ty
                self.blend(
                    tx,
                    ty,
                    (src.px[i], src.px[i + 1], src.px[i + 2]),
                    a / 255.0,
                )


# --------------------------------------------------------------------------
# PNG encoding, hand rolled so the tool has no dependencies at all.
# --------------------------------------------------------------------------


def _chunk(tag, data):
    return (
        struct.pack(">I", len(data))
        + tag
        + data
        + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    )


def encode_png(img):
    stride = img.w * 4
    raw = bytearray()
    for y in range(img.h):
        raw.append(0)  # filter type 0: none
        raw += img.px[y * stride : (y + 1) * stride]
    ihdr = struct.pack(">IIBBBBB", img.w, img.h, 8, 6, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + _chunk(b"IHDR", ihdr)
        + _chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + _chunk(b"IEND", b"")
    )


# --------------------------------------------------------------------------
# Geometry helpers.
# --------------------------------------------------------------------------


def quad(x0, y0, cx, cy, x1, y1, steps=24):
    """Quadratic bezier flattened to a flat point list."""
    out = []
    for i in range(steps + 1):
        t = i / steps
        u = 1 - t
        out.append(u * u * x0 + 2 * u * t * cx + t * t * x1)
        out.append(u * u * y0 + 2 * u * t * cy + t * t * y1)
    return out


def ellipse_pts(cx, cy, rx, ry, steps=40):
    """Points around an ellipse, first point repeated so `stroke` closes it.

    Used for the spectacle rims. A filled ellipse would have to be punched back
    out again, and that hole would swallow the eye underneath it; a ring drawn
    as a stroked loop leaves the face showing through untouched.
    """
    pts = [(cx + rx * math.cos(2 * math.pi * i / steps),
            cy + ry * math.sin(2 * math.pi * i / steps)) for i in range(steps + 1)]
    out = []
    for x, y in pts:
        out.append(x)
        out.append(y)
    return out


def spiral(cx, cy, r0, growth, start, end, steps=90):
    """Archimedean spiral. This is the koru: the unfurling fern frond that gives
    the product its name."""
    out = []
    for i in range(steps + 1):
        th = start + (end - start) * (i / steps)
        r = r0 + growth * (th - start)
        out.append(cx + r * math.cos(th))
        out.append(cy + r * math.sin(th))
    return out


# --------------------------------------------------------------------------
# The mascot.
# --------------------------------------------------------------------------

MOOD_CALM = "calm"
MOOD_HAPPY = "happy"


class Pose:
    """Every frame is the same drawing driven by these knobs, which is what
    keeps 32 frames consistent instead of 32 one off pictures."""

    def __init__(
        self,
        bob=0.0,
        frond_sway=0.0,
        eye_open=1.0,
        mood=MOOD_CALM,
        pupil_dx=0.0,
        pupil_dy=0.0,
        mouth_smile=1.0,
        # Resting arms hang down the sides of the body. The left angle is the
        # mirror of the right, because angles are measured in screen space.
        right_arm_angle=1.15,
        right_arm_out=0.0,
        left_arm_angle=1.99,
        left_arm_out=0.0,
        squash=0.0,
        think_dots=0,
        leaf_glint=False,
    ):
        self.bob = bob
        self.frond_sway = frond_sway
        self.eye_open = eye_open
        self.mood = mood
        self.pupil_dx = pupil_dx
        self.pupil_dy = pupil_dy
        self.mouth_smile = mouth_smile
        self.right_arm_angle = right_arm_angle
        self.right_arm_out = right_arm_out
        self.left_arm_angle = left_arm_angle
        self.left_arm_out = left_arm_out
        self.squash = squash
        self.think_dots = think_dots
        self.leaf_glint = leaf_glint


def draw_arm(r, pose, body_cx, body_cy, is_right):
    """One arm, drawn as a rounded limb ending in a mitten shaped leaf.

    The angle is measured from the shoulder in screen space, where positive y
    points down. The left arm is given the mirrored angle so both hang down the
    sides of the body at rest instead of one of them crossing in front of the
    shell, which is what an earlier version did.
    """
    s = SS
    angle = pose.right_arm_angle if is_right else pose.left_arm_angle
    out = pose.right_arm_out if is_right else pose.left_arm_out
    shoulder_x = body_cx + (1 if is_right else -1) * 33 * s
    shoulder_y = body_cy + 5 * s
    length = (17 + out) * s

    dir_x, dir_y = math.cos(angle), math.sin(angle)
    wrist_x = shoulder_x + dir_x * length
    wrist_y = shoulder_y + dir_y * length

    # Limb: a capsule, outlined then filled.
    r.stroke([shoulder_x, shoulder_y, wrist_x, wrist_y], [9.6 * s, 8.0 * s], LEAF)
    r.stroke([shoulder_x, shoulder_y, wrist_x, wrist_y], [6.2 * s, 4.8 * s], LEAF_LITE)

    # Hand: a rounded leaf sitting past the wrist, its long axis along the arm,
    # plus a soft point so it reads as a paw and not a ball.
    hand_x = wrist_x + dir_x * 7 * s
    hand_y = wrist_y + dir_y * 7 * s
    perp = angle + math.pi / 2

    r.ellipse(hand_x, hand_y, 11.5 * s, 8.4 * s, LEAF, rot=angle)
    r.ellipse(hand_x, hand_y, 8.4 * s, 5.4 * s, LEAF_LITE, rot=angle)

    tip_x = hand_x + dir_x * 9 * s
    tip_y = hand_y + dir_y * 9 * s
    blade = quad(
        hand_x + math.cos(perp) * 5.5 * s,
        hand_y + math.sin(perp) * 5.5 * s,
        tip_x + math.cos(perp) * 4.0 * s,
        tip_y + math.sin(perp) * 4.0 * s,
        tip_x,
        tip_y,
    ) + quad(
        tip_x,
        tip_y,
        tip_x - math.cos(perp) * 4.0 * s,
        tip_y - math.sin(perp) * 4.0 * s,
        hand_x - math.cos(perp) * 5.5 * s,
        hand_y - math.sin(perp) * 5.5 * s,
    )
    r.polygon(blade, LEAF)
    inner = quad(
        hand_x + math.cos(perp) * 3.2 * s,
        hand_y + math.sin(perp) * 3.2 * s,
        tip_x + math.cos(perp) * 2.2 * s,
        tip_y + math.sin(perp) * 2.2 * s,
        tip_x - dir_x * 1.5 * s,
        tip_y - dir_y * 1.5 * s,
    ) + quad(
        tip_x - dir_x * 1.5 * s,
        tip_y - dir_y * 1.5 * s,
        tip_x - math.cos(perp) * 2.2 * s,
        tip_y - math.sin(perp) * 2.2 * s,
        hand_x - math.cos(perp) * 3.2 * s,
        hand_y - math.sin(perp) * 3.2 * s,
    )
    r.polygon(inner, LEAF_LITE)


def draw_koru(r, pose, canvas=CELL, scale=CHAR_SCALE):
    """Draws Koru into a raster already scaled by SS.

    Every coordinate below is a logical offset from the canvas centre multiplied
    by `s`, so a bigger `canvas` or `scale` grows and re-centres the whole
    character without any of those numbers having to know about it. The design
    is authored against CELL, so `s` tracks the canvas and the mascot fills the
    same fraction of a 192 cell as it does of a 506 splash.
    """
    s = SS * scale * (canvas / float(CELL))
    centre = (canvas / 2.0) * SS
    bob_y = pose.bob * s
    cx = centre
    body_cx = cx
    body_cy = centre + 22 * s + bob_y
    stroke_w = 3.4 * s

    # Contact shadow, so the character sits on the ground instead of hovering.
    r.ellipse(centre, centre + 73 * s + bob_y * 0.35, 43 * s, 7.5 * s, INK, 0.10)
    r.ellipse(centre, centre + 73 * s + bob_y * 0.35, 26 * s, 4.5 * s, INK, 0.07)

    body_ry = 41 * s * (1 + pose.squash * 0.12)
    body_rx = 39 * s * (1 - pose.squash * 0.12)

    # Outline first, then the shell inset on top: one pass, correct silhouette.
    r.ellipse(body_cx, body_cy, body_rx + stroke_w / 2, body_ry + stroke_w / 2, LEAF)
    r.ellipse(body_cx, body_cy, body_rx, body_ry, CREAM)
    r.ellipse_inside(
        body_cx,
        body_cy + 6 * s,
        body_rx * 0.82,
        body_ry * 0.72,
        (body_cx, body_cy, body_rx, body_ry),
        LEAF_SOFT,
    )
    r.ellipse(body_cx - 13 * s, body_cy - 16 * s, 9 * s, 6 * s, (255, 255, 255), 0.75)

    # Arms sit behind the shell so they tuck in at the shoulder.
    draw_arm(r, pose, body_cx, body_cy, True)
    draw_arm(r, pose, body_cx, body_cy, False)

    # The koru frond: a coil that opens outward, tightest at the tip and widest
    # where it meets the stem.
    sway = pose.frond_sway
    stem_top_y = body_cy - body_ry * 0.88
    coil_cx = cx + sway * 5 * s
    coil_cy = stem_top_y - 20 * s
    coil_end = 1.8 * math.pi
    frond = spiral(coil_cx, coil_cy, 2.6 * s, 4.6 * s, 0.0, coil_end, steps=120)
    n = len(frond) // 2
    # Index 0 is the tight tip, index n-1 the outer base where the stem joins,
    # so the width has to grow along the path, not shrink.
    widths = [1.8 * s + 7.0 * s * (i / n) ** 0.8 for i in range(n)]
    r.stroke(frond, [w + stroke_w * 0.85 for w in widths], LEAF)
    r.stroke(frond, widths, LEAF_LITE)

    # The stem meets the coil at its outer end, so the frond reads as growing
    # out of the body rather than sitting on top of it.
    join_x = coil_cx + 26 * s * math.cos(coil_end)
    join_y = coil_cy + 26 * s * math.sin(coil_end)
    stem = [cx, stem_top_y + 4 * s, join_x, join_y]
    r.stroke(stem, [9.0 * s + stroke_w * 0.85, 7.4 * s + stroke_w * 0.85], LEAF)
    r.stroke(stem, [9.0 * s, 7.4 * s], LEAF_LITE)
    if pose.leaf_glint:
        r.circle(coil_cx - 12 * s, coil_cy - 12 * s, 3.0 * s, (255, 255, 255), 0.9)

    # Face.
    eye_dx = 17 * s
    eye_y = body_cy - 7 * s
    eye_l = body_cx - eye_dx
    eye_r = body_cx + eye_dx

    if pose.eye_open > 0.06:
        for ex in (eye_l, eye_r):
            opened = pose.eye_open
            ry = 8.4 * s * (0.18 + 0.82 * opened)
            r.ellipse(ex, eye_y, 6.6 * s * 0.55 + 2.4 * s * opened, ry + 2.2 * s, CREAM)
            r.ellipse(ex, eye_y, 6.6 * s * 0.55, ry, INK)
            r.circle(
                ex - 1.9 * s + pose.pupil_dx * s,
                eye_y - 2.4 * s + pose.pupil_dy * s,
                2.1 * s,
                (255, 255, 255),
                0.92,
            )

    if pose.mood != MOOD_HAPPY and pose.eye_open <= 0.55:
        closed = pose.eye_open < 0.2
        lid_y = eye_y if closed else eye_y + 5 * s * (1 - pose.eye_open)
        for ex in (eye_l, eye_r):
            curve = quad(ex - 7.5 * s, lid_y - 0.5 * s, ex, lid_y + 6.5 * s,
                         ex + 7.5 * s, lid_y - 0.5 * s)
            r.stroke(curve, [2.9 * s] * (len(curve) // 2), INK)

    if pose.mood == MOOD_HAPPY:
        # Upward arcs for delight. Only ever drawn on their own: combining them
        # with a closed-lid arc put two conflicting marks in the same place.
        for ex in (eye_l, eye_r):
            peak = quad(ex - 6.5 * s, eye_y + 2.5 * s, ex, eye_y - 6.5 * s,
                        ex + 6.5 * s, eye_y + 2.5 * s)
            r.stroke(peak, [2.9 * s] * (len(peak) // 2), INK)

    r.ellipse(body_cx - 30 * s, eye_y + 13 * s, 9.5 * s, 5.5 * s, CLAY, 0.30)
    r.ellipse(body_cx + 30 * s, eye_y + 13 * s, 9.5 * s, 5.5 * s, CLAY, 0.30)

    # Beard, laid down under the eyes so the spectacles and the eyes sit on top
    # of it rather than the other way round. It is a soft band along the jaw
    # rather than a fill: a filled shape would cover the mouth, and a character
    # whose smile has been swallowed by its own beard reads as a smudge.
    beard = quad(body_cx - 31 * s, body_cy + 11 * s, body_cx,
                 body_cy + 41 * s, body_cx + 31 * s, body_cy + 11 * s)
    r.stroke(beard, [10.5 * s] * (len(beard) // 2), INK, 0.17)
    r.stroke(beard, [5.0 * s] * (len(beard) // 2), INK, 0.13)

    mouth_y = body_cy + 14 * s
    spread = 11 * s * pose.mouth_smile
    depth = 7 * s * pose.mouth_smile
    mouth = quad(body_cx - spread, mouth_y - 1.5 * s, body_cx, mouth_y + depth,
                 body_cx + spread, mouth_y - 1.5 * s)
    r.stroke(mouth, [2.8 * s] * (len(mouth) // 2), INK)

    # Spectacles. Drawn after the eyes so the rims read as sitting on the face,
    # and as rings rather than lenses so the eye stays visible behind them, which
    # is the whole point of drawing a character in glasses rather than adding two
    # dark ovals and hoping.
    for ex in (eye_l, eye_r):
        r.stroke(
            ellipse_pts(ex, eye_y, 11.5 * s, 8.8 * s),
            [1.9 * s] * ((len(ellipse_pts(ex, eye_y, 11.5 * s, 8.8 * s))) // 2),
            INK, 0.80,
        )
    r.stroke_line(body_cx - 6.0 * s, eye_y - 1.2 * s, body_cx + 6.0 * s,
                  eye_y - 1.2 * s, 1.9 * s, INK, 0.80)
    for side in (-1, 1):
        r.stroke_line(body_cx + side * 28.5 * s, eye_y - 2.4 * s,
                      body_cx + side * 33.5 * s, eye_y - 4.4 * s,
                      1.8 * s, INK, 0.72)

    if pose.think_dots > 0:
        for i in range(pose.think_dots):
            dx = 30 * s + 11 * s * i
            dy = body_cy - 34 * s - 3 * s * (pose.think_dots - 1 - i)
            r.circle(body_cx + dx, dy, 3.6 * s, LEAF)


def pose_for(clip, frame, total):
    t = 0.0 if total <= 1 else frame / (total - 1)
    two_pi = 2 * math.pi
    if clip == "idle":
        return Pose(
            bob=math.sin(t * two_pi) * 1.6,
            frond_sway=math.sin(t * two_pi + 0.6) * 0.5,
            squash=math.sin(t * two_pi) * 0.25,
        )
    if clip == "blink":
        return Pose(eye_open=[1.0, 0.0, 0.0, 0.85][max(0, min(3, frame))],
                    bob=-0.4 + frame * 0.1)
    if clip == "wave":
        swing = math.sin(t * math.pi * 4)
        return Pose(
            bob=math.sin(t * two_pi) * 1.2,
            right_arm_angle=-1.35 + swing * 0.42,
            right_arm_out=6,
            left_arm_angle=2.15,
            mouth_smile=1.15,
            leaf_glint=frame % 2 == 0,
        )
    if clip == "think":
        return Pose(
            eye_open=0.82,
            pupil_dx=2.6,
            pupil_dy=-3.2,
            right_arm_angle=-2.05,
            right_arm_out=9,
            left_arm_angle=2.15,
            mouth_smile=0.35,
            think_dots=(frame % 4) + 1,
            bob=math.sin(t * two_pi) * 1.0,
        )
    if clip == "cheer":
        rise = math.sin(t * math.pi)
        return Pose(
            bob=-rise * 6,
            right_arm_angle=-1.95 + rise * 0.35,
            right_arm_out=8 + rise * 6,
            left_arm_angle=-1.35 - rise * 0.30,
            left_arm_out=8 + rise * 6,
            mood=MOOD_HAPPY,
            eye_open=0.0,
            mouth_smile=1.3,
            frond_sway=math.sin(t * math.pi * 4) * 0.8,
        )
    if clip == "greet":
        rise = math.sin(t * math.pi)
        return Pose(
            bob=-rise * 2.5,
            right_arm_angle=-1.25 + rise * 0.5,
            right_arm_out=5 + rise * 4,
            left_arm_angle=2.15,
            mouth_smile=1.1 + rise * 0.3,
        )
    raise KeyError(clip)


def render_pose(pose, canvas=CELL):
    """Renders one pose at `canvas` pixels square."""
    big = Raster(canvas * SS, canvas * SS)
    draw_koru(big, pose, canvas=canvas)
    return big.downsample(SS)


# --------------------------------------------------------------------------
# Icon and splash.
# --------------------------------------------------------------------------


def render_icon(size):
    """Flat launcher icon: solid leaf tile with the koru frond."""
    big = Raster(size, size)
    u = size / 256.0

    big.fill_rect(0, 0, size, size, LEAF)
    for y in range(size):
        big.fill_rect(0, y, size, y + 1, (255, 255, 255),
                      0.10 * math.sin(y / size * math.pi))

    frond = spiral(128 * u, 96 * u, 4 * u, 9.5 * u, 0.0, 1.75 * math.pi, steps=110)
    n = len(frond) // 2
    widths = [3.0 * u + 16 * u * (1.0 - i / n) ** 0.85 for i in range(n)]
    big.stroke(frond, [w + 7 * u for w in widths], INK, 0.16)
    big.stroke(frond, widths, (255, 255, 255), 0.94)

    big.stroke([128 * u, 196 * u, 128 * u, 112 * u], [16 * u, 14 * u], INK, 0.16)
    big.stroke([128 * u, 196 * u, 128 * u, 112 * u], [11 * u, 9 * u], (255, 255, 255), 0.94)

    for direction in (-1.0, 1.0):
        bx = 128 * u + direction * 46 * u
        by = 150 * u
        big.polygon(
            quad(128 * u, 178 * u, bx - direction * 34 * u, by - 40 * u,
                 bx + direction * 26 * u, by - 4 * u)
            + quad(bx + direction * 26 * u, by - 4 * u, bx - direction * 10 * u,
                   by + 22 * u, 128 * u, 178 * u),
            INK, 0.16,
        )
        big.polygon(
            quad(128 * u, 176 * u, bx - direction * 26 * u, by - 34 * u,
                 bx + direction * 20 * u, by - 6 * u)
            + quad(bx + direction * 20 * u, by - 6 * u, bx - direction * 6 * u,
                   by + 16 * u, 128 * u, 176 * u),
            (255, 255, 255), 0.86,
        )
    return big


def render_crest(size):
    """Just Koru on transparency, for the Android launch background.

    The launch window cannot animate, so it gets the same character as a still,
    on the same background colour the in-app splash uses. That is what makes the
    handoff from the system splash into the animated one read as one moment.
    """
    return render_pose(Pose(frond_sway=0.35, leaf_glint=True), canvas=size)


def render_splash(width):
    """Splash illustration: Koru standing on a leaf-soft hill.

    Composed in a 320 unit square and then scaled, so the mascot keeps its
    intended size relative to the hill instead of drifting when the output
    resolution changes.
    """
    logical = 320
    ss = 3
    u = width * ss / logical
    big = Raster(width * ss, width * ss)

    def lx(v):
        return v * u

    def ly(v):
        return v * u

    # Hill. The crest sits at y = 250 - sin(t*pi)*26, so its high point is 224.
    hill = []
    for i in range(97):
        t = i / 96
        hill.append(lx(t * logical))
        hill.append(ly(250 - math.sin(t * math.pi) * 26))
    hill += [lx(logical), ly(logical), lx(0), ly(logical)]
    big.polygon(hill, LEAF_SOFT)

    # Grass blades, taller and thinner than the first attempt so they read as
    # grass rather than dashes.
    for gx, gy, lean, tall in ((36, 244, 1.0, 46), (286, 246, -1.0, 42),
                               (68, 262, 0.9, 38), (252, 266, -0.95, 40),
                               (110, 258, 0.7, 30), (212, 260, -0.75, 32)):
        blade = quad(lx(gx), ly(gy), lx(gx + 18 * lean), ly(gy - tall * 0.55),
                     lx(gx + 34 * lean), ly(gy - tall))
        big.stroke(blade, [4.6 * u, 1.1 * u], LEAF, 0.42)

    # Koru, planted on the crest rather than hovering above it.
    mascot_px = int(150 * u)
    mascot = render_pose(Pose(frond_sway= 0.35, leaf_glint=True), canvas=mascot_px)
    big.blit(
        mascot,
        int(lx(logical / 2) - mascot.w / 2),
        int(ly(232) - mascot.h),
    )

    return big.downsample(ss)


# --------------------------------------------------------------------------
# main
# --------------------------------------------------------------------------


def write(path, img):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    data = encode_png(img)
    with open(path, "wb") as fh:
        fh.write(data)
    return len(data)


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

    needed = sum(c for _, c in CLIPS)
    capacity = ATLAS_COLS * ATLAS_ROWS
    if needed > capacity:
        sys.exit("atlas overflow: %d frames > %d slots" % (needed, capacity))

    atlas = Raster(ATLAS_COLS * CELL, ATLAS_ROWS * CELL)
    written = 0
    for clip, total in CLIPS:
        for f in range(total):
            idx = frames_before(clip) + f
            frame = render_pose(pose_for(clip, f, total))
            atlas.blit(frame, (idx % ATLAS_COLS) * CELL, (idx // ATLAS_COLS) * CELL)
            written += 1
    size = write(os.path.join(root, "assets/mascot/koru_atlas.png"), atlas)
    print("atlas   %dx%d  %d frames  %.1f KB" % (atlas.w, atlas.h, written, size / 1024))

    splash = render_splash(360)
    size = write(os.path.join(root, "assets/splash/koru_splash.png"), splash)
    print("splash  %dx%d  %.1f KB" % (splash.w, splash.h, size / 1024))

    crest = render_crest(288)
    size = write(
        os.path.join(root, "android/app/src/main/res/drawable-nodpi/koru_splash_crest.png"),
        crest,
    )
    print("crest   %dx%d  %.1f KB" % (crest.w, crest.h, size / 1024))

    densities = {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192,
    }
    res = os.path.join(root, "android/app/src/main/res")
    for folder, px in densities.items():
        size = write(os.path.join(res, folder, "ic_launcher.png"), render_icon(px))
        print("icon    %-16s %dpx  %.1f KB" % (folder, px, size / 1024))


if __name__ == "__main__":
    main()

"""Slice the mascot sprite atlas into single frames the home screen widget can use.

An AppWidget is drawn by the launcher, not by Flutter, so it cannot ask for a
frame out of a sprite sheet. RemoteViews only understands ordinary drawables, so
each mood the widget shows has to exist as its own PNG.

Done with the standard library rather than Pillow because the build has no image
libraries and this runs once, on one file, and the output is checked in.
"""

import struct
import sys
import zlib
from pathlib import Path

CELL = 192
COLS = 8


def read_png(path):
    data = Path(path).read_bytes()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", "not a png"

    pos = 8
    idat = bytearray()
    width = height = depth = colour = interlace = None
    palette = b""
    trns = b""

    while pos < len(data):
        (length,) = struct.unpack(">I", data[pos : pos + 4])
        kind = data[pos + 4 : pos + 8]
        body = data[pos + 8 : pos + 8 + length]
        pos += 12 + length

        if kind == b"IHDR":
            width, height, depth, colour, _comp, _filt, interlace = struct.unpack(
                ">IIBBBBB", body
            )
        elif kind == b"PLTE":
            palette = body
        elif kind == b"tRNS":
            trns = body
        elif kind == b"IDAT":
            idat += body
        elif kind == b"IEND":
            break

    assert depth == 8, f"only 8 bit images are handled, this one is {depth}"
    assert interlace == 0, "interlaced images are not handled"

    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[colour]
    raw = zlib.decompress(bytes(idat))

    stride = width * channels
    out = bytearray()
    previous = bytearray(stride)
    pos = 0

    for _ in range(height):
        ftype = raw[pos]
        pos += 1
        line = bytearray(raw[pos : pos + stride])
        pos += stride

        # Undo the per-scanline filter. Flutter writes these, so they have to be
        # undone rather than assumed away.
        if ftype == 1:
            for i in range(channels, stride):
                line[i] = (line[i] + line[i - channels]) & 0xFF
        elif ftype == 2:
            for i in range(stride):
                line[i] = (line[i] + previous[i]) & 0xFF
        elif ftype == 3:
            for i in range(stride):
                left = line[i - channels] if i >= channels else 0
                line[i] = (line[i] + ((left + previous[i]) >> 1)) & 0xFF
        elif ftype == 4:
            for i in range(stride):
                a = line[i - channels] if i >= channels else 0
                b = previous[i]
                c = previous[i - channels] if i >= channels else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pred = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pred) & 0xFF

        out += line
        previous = line

    # Everything downstream wants RGBA.
    rgba = bytearray(width * height * 4)
    for i in range(width * height):
        if colour == 6:
            rgba[i * 4 : i * 4 + 4] = out[i * 4 : i * 4 + 4]
        elif colour == 2:
            rgba[i * 4 : i * 4 + 3] = out[i * 3 : i * 3 + 3]
            rgba[i * 4 + 3] = 255
        elif colour == 0:
            v = out[i]
            rgba[i * 4 : i * 4 + 4] = bytes((v, v, v, 255))
        elif colour == 4:
            v = out[i * 2]
            rgba[i * 4 : i * 4 + 4] = bytes((v, v, v, out[i * 2 + 1]))
        elif colour == 3:
            idx = out[i]
            rgba[i * 4 : i * 4 + 3] = palette[idx * 3 : idx * 3 + 3]
            rgba[i * 4 + 3] = trns[idx] if idx < len(trns) else 255
    return width, height, rgba


def write_png(path, width, height, rgba):
    raw = bytearray()
    stride = width * 4
    for y in range(height):
        raw.append(0)  # filter type none, which is always legal
        raw += rgba[y * stride : (y + 1) * stride]

    def chunk(kind, body):
        return (
            struct.pack(">I", len(body))
            + kind
            + body
            + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)
        )

    out = b"\x89PNG\r\n\x1a\n"
    out += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    out += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    out += chunk(b"IEND", b"")
    Path(path).write_bytes(out)


def frame(width, height, rgba, index):
    """The pixels of atlas frame [index], which is a fixed size cell."""
    col, row = index % COLS, index // COLS
    x0, y0 = col * CELL, row * CELL
    if x0 + CELL > width or y0 + CELL > height:
        raise SystemExit(f"frame {index} is outside a {width}x{height} atlas")
    out = bytearray(CELL * CELL * 4)
    for y in range(CELL):
        src = ((y0 + y) * width + x0) * 4
        out[y * CELL * 4 : (y + 1) * CELL * 4] = rgba[src : src + CELL * 4]
    return out


def main():
    atlas, outdir = sys.argv[1], sys.argv[2]
    Path(outdir).mkdir(parents=True, exist_ok=True)
    width, height, rgba = read_png(atlas)
    print(f"atlas {width}x{height}")

    # Frame numbers from lib/mascot/mascot_clips.dart. idle 0, blink 6,
    # wave 10, think 18, cheer 22, greet 28.
    wanted = {"koru_idle": 0, "koru_wave": 10, "koru_think": 18, "koru_cheer": 22}
    for name, index in wanted.items():
        write_png(Path(outdir) / f"{name}.png", CELL, CELL, frame(width, height, rgba, index))
        print(f"  {name}.png <- frame {index}")


if __name__ == "__main__":
    main()
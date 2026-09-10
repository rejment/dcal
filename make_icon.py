#!/usr/bin/env python3
"""Draw the app icon: one day, top to bottom.

The icon is the app's own idea at 1024 pixels - midnight at both ends, dawn
and dusk warm, midday bright - with the white "now" line across it and three
notches for the things on the timeline. Pure stdlib, so CI can regenerate it.

    ./make_icon.py            # -> ios/Dcal/Assets.xcassets/AppIcon.appiconset/icon-1024.png
"""

import struct
import zlib
from pathlib import Path

SIZE = 1024
SS = 2  # supersample, then average down so the circle has smooth edges

# The same stops as SkyPalette.swift, lifted for a home screen: the app is
# read in a dark room, an icon sits next to Photos and Maps.
STOPS = [
    (0.0, (5, 7, 15)),
    (4.2, (8, 12, 28)),
    (5.8, (26, 32, 71)),
    (7.0, (74, 52, 80)),
    (8.4, (30, 50, 94)),
    (12.0, (42, 75, 124)),
    (16.0, (38, 66, 110)),
    (18.6, (82, 52, 76)),
    (20.6, (22, 28, 56)),
    (24.0, (5, 7, 15)),
]
LIFT = 1.55

NOTCHES = [  # (hour, colour, width)
    (7.4, (245, 196, 107), 232),
    (10.1, (79, 201, 174), 140),
    (16.3, (242, 128, 159), 186),
]
NOW_HOUR = 13.1


def sky(hour):
    for i in range(len(STOPS) - 1):
        if hour <= STOPS[i + 1][0]:
            lo, hi = STOPS[i], STOPS[i + 1]
            t = (hour - lo[0]) / (hi[0] - lo[0])
            return tuple(
                min(255, int((lo[1][c] + (hi[1][c] - lo[1][c]) * t) * LIFT))
                for c in range(3)
            )
    return STOPS[-1][1]


def draw():
    n = SIZE * SS
    rows = []
    for y in range(n):
        hour = y / n * 24
        base = sky(hour)
        row = bytearray(base * n)

        for notch_hour, colour, width in NOTCHES:
            top = notch_hour / 24 * n - 7.5 * SS
            if top <= y < top + 15 * SS:
                x0, x1 = 96 * SS, (96 + width) * SS
                row[x0 * 3:x1 * 3] = bytes(colour) * (x1 - x0)

        now_y = NOW_HOUR / 24 * n
        if abs(y - now_y) < 2.6 * SS:
            row[96 * SS * 3:] = b"\xff" * ((n - 96 * SS) * 3)
        # The marker sitting on the line, the way it sits on the ribbon.
        cx, cy, r = 140 * SS, now_y, 21 * SS
        if abs(y - cy) <= r:
            half = int((r * r - (y - cy) ** 2) ** 0.5)
            row[(cx - half) * 3:(cx + half) * 3] = b"\xff" * (half * 2 * 3)
        rows.append(row)

    # Average the supersampled image down (SS is 2, so four samples each).
    out = []
    for y in range(SIZE):
        top, bottom = rows[2 * y], rows[2 * y + 1]
        line = bytearray(SIZE * 3)
        for i in range(SIZE * 3):
            p = (i // 3) * 6 + (i % 3)
            line[i] = (top[p] + top[p + 3] + bottom[p] + bottom[p + 3]) >> 2
        out.append(line)
    return out


def write_png(path, rows):
    raw = b"".join(b"\x00" + bytes(row) for row in rows)

    def chunk(kind, data):
        return (
            struct.pack(">I", len(data))
            + kind
            + data
            + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
        )

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )


if __name__ == "__main__":
    target = Path(__file__).parent / "ios/Dcal/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
    write_png(target, draw())
    print(f"wrote {target} ({target.stat().st_size} bytes)")

# Draws the white Touch Bar icons (transparent background) as PNGs, no dependencies.
#   python3 make_icon.py <icon> <out.png>    icon: bot (Cowork) | terminal (Code)
import struct, zlib, sys
S, SS = 48, 4                      # output size, supersampling

def rrect(u, v, x0, y0, x1, y1, r):
    cx = min(max(u, x0 + r), x1 - r); cy = min(max(v, y0 + r), y1 - r)
    return x0 <= u <= x1 and y0 <= v <= y1 and (u - cx) ** 2 + (v - cy) ** 2 <= r * r

def circ(u, v, cx, cy, r):
    return (u - cx) ** 2 + (v - cy) ** 2 <= r * r

def seg(u, v, x0, y0, x1, y1, w):
    # Within w/2 of the segment (round caps).
    dx, dy = x1 - x0, y1 - y0
    t = max(0, min(1, ((u - x0) * dx + (v - y0) * dy) / (dx * dx + dy * dy)))
    return (u - x0 - t * dx) ** 2 + (v - y0 - t * dy) ** 2 <= (w / 2) ** 2

def bot(u, v):
    eye = circ(u, v, 17, 25, 4.2) or circ(u, v, 31, 25, 4.2)
    mouth = rrect(u, v, 17, 33, 31, 36, 1.5)
    head = rrect(u, v, 7, 13, 41, 43, 8)
    ears = rrect(u, v, 2, 22, 7, 33, 2) or rrect(u, v, 41, 22, 46, 33, 2)
    antenna = rrect(u, v, 22.5, 6, 25.5, 13, 1) or circ(u, v, 24, 5, 3.5)
    return (head and not eye and not mouth) or ears or antenna

def terminal(u, v):
    # A window outline with a ">_" prompt inside.
    frame = rrect(u, v, 3, 7, 45, 41, 7) and not rrect(u, v, 7, 11, 41, 37, 4)
    chevron = seg(u, v, 13, 17, 21, 24, 4) or seg(u, v, 21, 24, 13, 31, 4)
    underscore = seg(u, v, 25, 31, 35, 31, 4)
    return frame or chevron or underscore

def render(shape, path):
    rows = []
    for y in range(S):
        row = bytearray([0])
        for x in range(S):
            a = sum(shape((x * SS + i + .5) / SS, (y * SS + j + .5) / SS) for i in range(SS) for j in range(SS))
            row += bytes([255, 255, 255, round(255 * a / SS / SS)])
        rows.append(bytes(row))
    def chunk(t, d): return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d))
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", S, S, 8, 6, 0, 0, 0)) \
        + chunk(b"IDAT", zlib.compress(b"".join(rows))) + chunk(b"IEND", b"")
    open(path, "wb").write(png)

render({"bot": bot, "terminal": terminal}[sys.argv[1]], sys.argv[2])

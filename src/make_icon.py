# Draws a white robot head (transparent background) as a PNG, no dependencies.
import struct, zlib, sys
S, SS = 48, 4                      # output size, supersampling
N = S * SS
def inside(x, y):
    u, v = x / SS, y / SS          # coords in 48px space
    def rrect(x0, y0, x1, y1, r):
        cx = min(max(u, x0 + r), x1 - r); cy = min(max(v, y0 + r), y1 - r)
        return x0 <= u <= x1 and y0 <= v <= y1 and (u - cx) ** 2 + (v - cy) ** 2 <= r * r
    circ = lambda cx, cy, r: (u - cx) ** 2 + (v - cy) ** 2 <= r * r
    eye = circ(17, 25, 4.2) or circ(31, 25, 4.2)
    mouth = rrect(17, 33, 31, 36, 1.5)
    head = rrect(7, 13, 41, 43, 8)
    ears = rrect(2, 22, 7, 33, 2) or rrect(41, 22, 46, 33, 2)
    antenna = rrect(22.5, 6, 25.5, 13, 1) or circ(24, 5, 3.5)
    return (head and not eye and not mouth) or ears or antenna
rows = []
for y in range(S):
    row = bytearray([0])
    for x in range(S):
        a = sum(inside(x * SS + i + .5, y * SS + j + .5) for i in range(SS) for j in range(SS))
        row += bytes([255, 255, 255, round(255 * a / SS / SS)])
    rows.append(bytes(row))
def chunk(t, d): return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d))
png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", S, S, 8, 6, 0, 0, 0)) \
    + chunk(b"IDAT", zlib.compress(b"".join(rows))) + chunk(b"IEND", b"")
open(sys.argv[1], "wb").write(png)

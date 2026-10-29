# Touch Bar icons as PNGs, no dependencies.
#   python3 make_icon.py <icon> <out.png>                draw a built-in white glyph: bot | terminal
#   python3 make_icon.py badge <glyph.png> <#rrggbb> <out.png>
#        put a white glyph (any RGBA PNG) on a colored rounded square: the tile's state color
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
    write(rows, path)

def read_alpha(path):
    # Alpha channel of an 8-bit RGBA PNG, as a function of (u, v) in 48px space.
    d = open(path, "rb").read()
    w, h, depth, ctype = struct.unpack(">IIBB", d[16:26])
    assert depth == 8 and ctype == 6, "glyph must be an 8-bit RGBA PNG"
    i, idat = 8, b""
    while i < len(d):
        n = struct.unpack(">I", d[i:i + 4])[0]
        if d[i + 4:i + 8] == b"IDAT": idat += d[i + 8:i + 8 + n]
        i += 12 + n
    raw, stride, prev, px = zlib.decompress(idat), w * 4, bytearray(w * 4), []
    for y in range(h):
        f, line = raw[y * (stride + 1)], bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        for x in range(stride):
            a = line[x - 4] if x >= 4 else 0
            b, c = prev[x], prev[x - 4] if x >= 4 else 0
            if f == 1: line[x] = (line[x] + a) & 255
            elif f == 2: line[x] = (line[x] + b) & 255
            elif f == 3: line[x] = (line[x] + (a + b) // 2) & 255
            elif f == 4:
                p = a + b - c; pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[x] = (line[x] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        px.append(line); prev = line
    return lambda u, v: px[min(h - 1, int(v * h / S))][min(w - 1, int(u * w / S)) * 4 + 3] / 255

def badge(glyph_path, color, path):
    r, g, b = (int(color.lstrip("#")[k:k + 2], 16) for k in (0, 2, 4))
    alpha = read_alpha(glyph_path)
    rows = []
    for y in range(S):
        row = bytearray([0])
        for x in range(S):
            bg = gl = 0
            for i in range(SS):
                for j in range(SS):
                    u, v = (x * SS + i + .5) / SS, (y * SS + j + .5) / SS
                    if rrect(u, v, 0, 0, S, S, 10):
                        bg += 1
                        # Glyph at 70% size, centered.
                        gu, gv = (u - S * .15) / .7, (v - S * .15) / .7
                        if 0 <= gu < S and 0 <= gv < S: gl += alpha(gu, gv)
            bg, gl = bg / SS / SS, gl / SS / SS
            row += bytes([round(r + (255 - r) * gl / max(bg, 1e-9)), round(g + (255 - g) * gl / max(bg, 1e-9)),
                          round(b + (255 - b) * gl / max(bg, 1e-9)), round(255 * bg)])
        rows.append(bytes(row))
    write(rows, path)

def write(rows, path):
    def chunk(t, d): return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d))
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", S, S, 8, 6, 0, 0, 0)) \
        + chunk(b"IDAT", zlib.compress(b"".join(rows))) + chunk(b"IEND", b"")
    open(path, "wb").write(png)

if sys.argv[1] == "badge":
    badge(sys.argv[2], sys.argv[3], sys.argv[4])
else:
    render({"bot": bot, "terminal": terminal}[sys.argv[1]], sys.argv[2])

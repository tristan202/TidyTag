"""Makes TidyTag.ico (needs Pillow + numpy): cuts the app tile out of a JPEG with a painted (grey)
checkerboard and writes the cut-out PNG (res/logo/tidytag.png) and the ICO.
The mask comes from the pixels: the tile is coloured, the checkerboard and its shadow are grey.
usage: icon_cut.py <src.jpg> <out.png> <out.ico>"""
import sys
import numpy as np
from PIL import Image, ImageFilter

src, out_png, out_ico = sys.argv[1:4]

im = Image.open(src).convert('RGB')
a = np.asarray(im).astype(int)
sat = a.max(axis=2) - a.min(axis=2)
tile = sat > 18

# the tile is convex: fill each row and each column between its outermost tile pixels,
# keeping only rows/columns that clearly belong to the tile (drops JPEG noise specks)
H, W = tile.shape
rowfill = np.zeros_like(tile)
colfill = np.zeros_like(tile)
for y in range(H):
    xs = np.where(tile[y])[0]
    if len(xs) > 40:
        rowfill[y, xs[0]:xs[-1] + 1] = True
for x in range(W):
    ys = np.where(tile[:, x])[0]
    if len(ys) > 40:
        colfill[ys[0]:ys[-1] + 1, x] = True
mask = rowfill & colfill
ys, xs = np.where(mask)
top, bottom, left, right = ys.min(), ys.max(), xs.min(), xs.max()
print('bbox', left, top, right, bottom, 'size', right - left + 1, bottom - top + 1)

m = Image.fromarray((mask * 255).astype(np.uint8))
# shave 2 px off the edge (JPEG ringing against the grey) and soften the step
m = m.filter(ImageFilter.MinFilter(5)).filter(ImageFilter.GaussianBlur(1.2))
rgba = im.convert('RGBA')
rgba.putalpha(m)
crop = rgba.crop((left, top, right + 1, bottom + 1))
w, h = crop.size
side = max(w, h)
sq = Image.new('RGBA', (side, side), (0, 0, 0, 0))
sq.paste(crop, ((side - w) // 2, (side - h) // 2))
sq.save(out_png)

sizes = [16, 20, 24, 32, 40, 48, 64, 128, 256]
frames = [sq.resize((s, s), Image.LANCZOS) for s in sizes]
# small sizes: a touch of sharpening against the blur from the big downscale
frames = [f.filter(ImageFilter.UnsharpMask(radius=0.6, percent=60, threshold=0)) if s <= 48 else f
          for f, s in zip(frames, sizes)]


def bmp_entry(f):
    """Classic ICO image: BITMAPINFOHEADER, 32-bit BGRA bottom-up, then the 1-bit AND mask."""
    import struct
    s = f.width
    px = np.asarray(f.convert('RGBA'))[::-1]  # bottom-up
    bgra = px[..., [2, 1, 0, 3]].astype(np.uint8).tobytes()
    row = ((s + 31) // 32) * 4
    andmask = bytearray()
    for y in range(s):
        bits = bytearray(row)
        for x in range(s):
            if px[y, x, 3] == 0:
                bits[x // 8] |= 0x80 >> (x % 8)
        andmask += bits
    hdr = struct.pack('<IiiHHIIiiII', 40, s, s * 2, 1, 32, 0, len(bgra) + len(andmask), 0, 0, 0, 0)
    return hdr + bgra + bytes(andmask)


def png_entry(f):
    import io
    b = io.BytesIO()
    f.save(b, format='PNG')
    return b.getvalue()


def write_ico(path, frames):
    """Bitmaps up to 128 px (readable everywhere), PNG for 256 px (the Vista+ convention)."""
    import struct
    datas = [png_entry(f) if f.width >= 256 else bmp_entry(f) for f in frames]
    out = struct.pack('<HHH', 0, 1, len(frames))
    offset = 6 + 16 * len(frames)
    for f, d in zip(frames, datas):
        w = f.width if f.width < 256 else 0
        out += struct.pack('<BBBBHHII', w, w, 0, 0, 1, 32, len(d), offset)
        offset += len(d)
    with open(path, 'wb') as fh:
        fh.write(out + b''.join(datas))


write_ico(out_ico, frames)
preview = Image.new('RGBA', (sum(sizes) + 10 * len(sizes), 256 + 20), (235, 235, 235, 255))
x = 5
for f in frames:
    preview.alpha_composite(f, (x, 10))
    x += f.width + 10
preview.save(out_png.replace('.png', '_sizes.png'))
print('png', sq.size, 'ico', sizes)

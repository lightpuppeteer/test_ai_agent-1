"""Paints the island's signboards and movie posters (PNG textures).

    python3 tools/sign_art/make_signs.py

Everything is drawn at 2x and downsampled. Output: assets/signs/*.png
"""
import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets", "signs")
FONTS = os.path.join(ROOT, "assets", "fonts")
SS = 2  # supersampling


def font(px, weight=700, family="Fredoka"):
    f = ImageFont.truetype(os.path.join(FONTS, family + ".ttf"), int(px * SS))
    try:
        axes = f.get_variation_axes()
        vals = []
        for a in axes:
            n = a["name"].decode() if isinstance(a["name"], bytes) else a["name"]
            vals.append(weight if n == "Weight" else a["default"])
        f.set_variation_by_axes(vals)
    except Exception:
        pass
    return f


def rgb(h, a=255):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)) + (a,)


def canvas(w, h, bg=(0, 0, 0, 0)):
    im = Image.new("RGBA", (w * SS, h * SS), bg)
    return im, ImageDraw.Draw(im)


def save(im, name):
    w, h = im.size
    im = im.resize((w // SS, h // SS), Image.LANCZOS)
    os.makedirs(OUT, exist_ok=True)
    im.save(os.path.join(OUT, name + ".png"))
    print("wrote", name, im.size)


def S(v):
    return int(v * SS)


def text(d, xy, s, f, fill, stroke=0, stroke_fill=None, anchor="mm", shadow=None, spacing=0):
    x, y = S(xy[0]), S(xy[1])
    if shadow:
        d.text((x + S(shadow[0]), y + S(shadow[1])), s, font=f, fill=shadow[2], anchor=anchor,
               stroke_width=S(stroke), stroke_fill=shadow[2], spacing=S(spacing), align="center")
    d.text((x, y), s, font=f, fill=fill, anchor=anchor, stroke_width=S(stroke),
           stroke_fill=stroke_fill or fill, spacing=S(spacing), align="center")


def rrect(d, box, r, fill, outline=None, width=0):
    d.rounded_rectangle([S(box[0]), S(box[1]), S(box[2]), S(box[3])], radius=S(r), fill=fill,
                        outline=outline, width=S(width))


def wood(im, box, base, r=18, plank_h=34, seed=1):
    """Rounded wooden board with planks and grain."""
    rnd = random.Random(seed)
    x0, y0, x1, y1 = box
    layer, d = canvas(im.size[0] // SS, im.size[1] // SS)
    y = y0
    i = 0
    while y < y1:
        c = tuple(max(0, min(255, int(base[k] * (0.92 + 0.12 * ((i * 37) % 5) / 4)))) for k in range(3)) + (255,)
        d.rectangle([S(x0), S(y), S(x1), S(min(y + plank_h, y1))], fill=c)
        for g in range(5):
            gy = y + rnd.uniform(4, plank_h - 4)
            gx = rnd.uniform(x0, x1 - 60)
            d.line([S(gx), S(gy), S(gx + rnd.uniform(40, 160)), S(gy + rnd.uniform(-1.5, 1.5))],
                   fill=tuple(int(v * 0.82) for v in base[:3]) + (140,), width=S(2))
        d.line([S(x0), S(y + plank_h), S(x1), S(y + plank_h)], fill=tuple(int(v * 0.65) for v in base[:3]) + (255,), width=S(2.5))
        y += plank_h
        i += 1
    mask = Image.new("L", layer.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([S(x0), S(y0), S(x1), S(y1)], radius=S(r), fill=255)
    im.paste(layer, (0, 0), mask)


def heart(d, cx, cy, s, fill, outline=None, width=0):
    pts = []
    for i in range(80):
        t = 2 * math.pi * i / 80
        x = 16 * math.sin(t) ** 3
        y = -(13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t))
        pts.append((S(cx + x * s / 16), S(cy + y * s / 16)))
    d.polygon(pts, fill=fill, outline=outline, width=S(width) if width else 0)


def star(d, cx, cy, r, fill, points=5, inner=0.45, rot=-90):
    pts = []
    for i in range(points * 2):
        rr = r if i % 2 == 0 else r * inner
        a = math.radians(rot + i * 180 / points)
        pts.append((S(cx + math.cos(a) * rr), S(cy + math.sin(a) * rr)))
    d.polygon(pts, fill=fill)


def flower(d, cx, cy, r, petal, center=rgb("ffd84d")):
    for i in range(5):
        a = math.radians(i * 72 - 90)
        px, py = cx + math.cos(a) * r * 0.62, cy + math.sin(a) * r * 0.62
        d.ellipse([S(px - r * 0.48), S(py - r * 0.48), S(px + r * 0.48), S(py + r * 0.48)], fill=petal)
    d.ellipse([S(cx - r * 0.36), S(cy - r * 0.36), S(cx + r * 0.36), S(cy + r * 0.36)], fill=center)


def pizza_slice(d, cx, cy, s, rot=0):
    def P(x, y):
        a = math.radians(rot)
        return (S(cx + (x * math.cos(a) - y * math.sin(a)) * s), S(cy + (x * math.sin(a) + y * math.cos(a)) * s))
    d.polygon([P(-0.5, -0.45), P(0.5, -0.45), P(0, 0.6)], fill=rgb("ffcc4d"))
    d.polygon([P(-0.56, -0.62), P(0.56, -0.62), P(0.5, -0.4), P(-0.5, -0.4)], fill=rgb("c9853f"))
    for px, py in [(-0.18, -0.2), (0.17, -0.15), (0.0, 0.18)]:
        x, y = P(px, py)
        r = S(0.11 * s)
        d.ellipse([x - r, y - r, x + r, y + r], fill=rgb("d9412f"))


def film_reel(d, cx, cy, r, col, hole):
    d.ellipse([S(cx - r), S(cy - r), S(cx + r), S(cy + r)], fill=col)
    for i in range(5):
        a = math.radians(i * 72 - 90)
        hx, hy = cx + math.cos(a) * r * 0.55, cy + math.sin(a) * r * 0.55
        d.ellipse([S(hx - r * 0.2), S(hy - r * 0.2), S(hx + r * 0.2), S(hy + r * 0.2)], fill=hole)
    d.ellipse([S(cx - r * 0.13), S(cy - r * 0.13), S(cx + r * 0.13), S(cy + r * 0.13)], fill=hole)


def palm(d, x, y, s, trunk=rgb("a8683f"), leaf=rgb("4fb35c")):
    for i in range(7):
        t = i / 6
        px, py = x + math.sin(t * 1.3) * s * 0.18, y - t * s
        r = s * 0.07
        d.ellipse([S(px - r), S(py - r * 1.2), S(px + r), S(py + r * 1.2)], fill=trunk)
    tx, ty = x + math.sin(1.3) * s * 0.18, y - s
    for ang in [200, 235, 280, 320, 355, 25]:
        a = math.radians(ang)
        pts = [(S(tx + math.cos(a) * s * 0.55 * k / 6), S(ty + math.sin(a) * s * 0.55 * k / 6 + (k / 6) ** 2 * s * 0.18)) for k in range(7)]
        d.line(pts, fill=leaf, width=S(s * 0.12), joint="curve")


def bulbs_border(d, box, step, r, on, off=None, phase=0):
    x0, y0, x1, y1 = box
    pts = []
    x = x0
    while x <= x1 + 0.1:
        pts.append((x, y0)); pts.append((x, y1)); x += step
    y = y0 + step
    while y < y1 - 0.1:
        pts.append((x0, y)); pts.append((x1, y)); y += step
    for i, (px, py) in enumerate(pts):
        d.ellipse([S(px - r * 1.7), S(py - r * 1.7), S(px + r * 1.7), S(py + r * 1.7)], fill=on[:3] + (60,))
        d.ellipse([S(px - r), S(py - r), S(px + r), S(py + r)], fill=on)


def soft_shadow(im, box, r, off=(0, 6), alpha=90, blur=10):
    sh = Image.new("RGBA", im.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle([S(box[0] + off[0]), S(box[1] + off[1]), S(box[2] + off[0]), S(box[3] + off[1])],
                                         radius=S(r), fill=(40, 20, 10, alpha))
    sh = sh.filter(ImageFilter.GaussianBlur(S(blur)))
    return Image.alpha_composite(sh, im)


# ---------------------------------------------------------------------------
# Signs
# ---------------------------------------------------------------------------

def pizzeria():
    W, H = 1024, 256
    im, d = canvas(W, H)
    rrect(d, (6, 6, W - 6, H - 6), 40, rgb("7a3b22"))
    # Red & cream stripes framed in gold.
    layer, ld = canvas(W, H)
    for i in range(0, W, 64):
        ld.rectangle([S(i), 0, S(i + 32), S(H)], fill=rgb("e2483d"))
        ld.rectangle([S(i + 32), 0, S(i + 64), S(H)], fill=rgb("fff3df"))
    mask = Image.new("L", im.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([S(22), S(22), S(W - 22), S(H - 22)], radius=S(28), fill=255)
    im.paste(layer, (0, 0), mask)
    d = ImageDraw.Draw(im)
    rrect(d, (120, 40, W - 120, H - 40), 50, rgb("fff8ec"), outline=rgb("e0a93b"), width=7)
    text(d, (W / 2, H / 2 - 18), "Pizzeria Amore", font(92, 700), rgb("d6362c"), stroke=5, stroke_fill=rgb("fff8ec"),
         shadow=(0, 5, rgb("9d2a1f", 120)))
    text(d, (W / 2, H / 2 + 52), "~ forno a legna · since forever ~", font(26, 600, "Nunito"), rgb("8a5a3a"))
    pizza_slice(d, 72, H / 2, 82, rot=-20)
    pizza_slice(d, W - 72, H / 2, 82, rot=20)
    heart(d, W / 2 + 300, H / 2 - 50, 16, rgb("e2483d"))
    save(im, "pizzeria")


def cinema():
    W, H = 1024, 300
    im, d = canvas(W, H)
    rrect(d, (6, 6, W - 6, H - 6), 30, rgb("2b2142"))
    rrect(d, (26, 26, W - 26, H - 26), 22, rgb("3b2d5e"), outline=rgb("f2c14e"), width=5)
    bulbs_border(d, (42, 42, W - 42, H - 42), 34, 7, rgb("ffe58a"))
    text(d, (W / 2, 112), "CINEMA PARAÍSO", font(80, 700), rgb("ffd45c"), stroke=4, stroke_fill=rgb("8a4b16"),
         shadow=(0, 6, rgb("120c20", 160)))
    rrect(d, (W / 2 - 220, 178, W / 2 + 220, 238), 28, rgb("e2483d"))
    text(d, (W / 2, 208), "NOW SHOWING", font(34, 700), rgb("fff3df"))
    star(d, W / 2 - 180, 208, 15, rgb("ffd45c"))
    star(d, W / 2 + 180, 208, 15, rgb("ffd45c"))
    film_reel(d, 105, 150, 44, rgb("ffd45c"), rgb("3b2d5e"))
    film_reel(d, W - 105, 150, 44, rgb("ffd45c"), rgb("3b2d5e"))
    save(im, "cinema")


def hotel():
    W, H = 900, 220
    im, d = canvas(W, H)
    rrect(d, (6, 6, W - 6, H - 6), 60, rgb("f7fbfb"), outline=rgb("2f8f99"), width=8)
    rrect(d, (26, 26, W - 26, H - 26), 46, rgb("5cc4cc"))
    # Waves along the bottom.
    for k in range(3):
        y = H - 58 + k * 12
        pts = [(S(x), S(y + math.sin(x / 26 + k) * 5)) for x in range(40, W - 40, 6)]
        d.line(pts, fill=rgb("e9fbfb", 180 - k * 40), width=S(4))
    text(d, (W / 2, 92), "Hotel & Spa", font(88, 700), rgb("ffffff"), stroke=4, stroke_fill=rgb("2f8f99"),
         shadow=(0, 5, rgb("1f6d75", 140)))
    for i, x in enumerate([W / 2 - 80, W / 2 - 40, W / 2, W / 2 + 40, W / 2 + 80]):
        star(d, x, 150, 13, rgb("ffd45c"))
    # Bubbles
    for (x, y, r) in [(90, 70, 22), (130, 120, 14), (78, 140, 10), (W - 90, 80, 20), (W - 130, 130, 12), (W - 80, 150, 9)]:
        d.ellipse([S(x - r), S(y - r), S(x + r), S(y + r)], outline=rgb("ffffff", 230), width=S(4))
    save(im, "hotel")


def oasis_arrow():
    W, H = 640, 220
    im, d = canvas(W, H)
    pts = [(20, 40), (W - 120, 40), (W - 20, H / 2), (W - 120, H - 40), (20, H - 40)]
    sh = Image.new("RGBA", im.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).polygon([(S(x), S(y + 8)) for x, y in pts], fill=(40, 20, 10, 110))
    im = Image.alpha_composite(im, sh.filter(ImageFilter.GaussianBlur(S(6))))
    layer, _ = canvas(W, H)
    wood(layer, (0, 0, W, H), rgb("c98a52"), r=0, plank_h=48, seed=5)
    mask = Image.new("L", im.size, 0)
    ImageDraw.Draw(mask).polygon([(S(x), S(y)) for x, y in pts], fill=255)
    im.paste(layer, (0, 0), mask)
    d = ImageDraw.Draw(im)
    d.line([(S(x), S(y)) for x, y in pts + [pts[0]]], fill=rgb("7a4a28"), width=S(7), joint="curve")
    text(d, (W / 2 - 30, H / 2 + 2), "Oasis", font(96, 700), rgb("fff6e0"), stroke=5, stroke_fill=rgb("7a4a28"))
    palm(d, 86, H / 2 + 50, 100)
    save(im, "oasis")


def garden():
    W, H = 760, 200
    im, d = canvas(W, H)
    im = soft_shadow(im, (10, 14, W - 10, H - 10), 50)
    wood(im, (10, 10, W - 10, H - 14), rgb("b97a46"), r=50, plank_h=46, seed=3)
    d = ImageDraw.Draw(im)
    rrect(d, (10, 10, W - 10, H - 14), 50, None, outline=rgb("6e4325"), width=7)
    text(d, (W / 2, H / 2 - 2), "The Garden", font(84, 700), rgb("fff3e6"), stroke=5, stroke_fill=rgb("8e3f62"))
    for (x, y, r, c) in [(60, 60, 26, rgb("ff8fb1")), (100, 130, 20, rgb("ffd45c")), (W - 60, 60, 26, rgb("c49bff")),
                         (W - 100, 132, 20, rgb("ff8fb1")), (W / 2 + 230, 40, 14, rgb("ffffff"))]:
        flower(d, x, y, r, c)
    save(im, "garden")


def house_plaque():
    W, H = 520, 280
    im, d = canvas(W, H)
    im = soft_shadow(im, (14, 14, W - 14, H - 14), 60)
    wood(im, (14, 10, W - 14, H - 18), rgb("d8a06a"), r=60, plank_h=52, seed=8)
    d = ImageDraw.Draw(im)
    rrect(d, (14, 10, W - 14, H - 18), 60, None, outline=rgb("7a4a28"), width=7)
    heart(d, W / 2, 62, 34, rgb("ff6f91"), outline=rgb("ffffff"), width=4)
    text(d, (W / 2, 138), "Tatiana & Marco", font(58, 700), rgb("5b3a8c"), stroke=3, stroke_fill=rgb("fff3e6"))
    text(d, (W / 2, 200), "& Yoggi (the boss)", font(30, 700, "Nunito"), rgb("8a5a3a"))
    save(im, "our_house")


def her_plaque():
    W, H = 460, 200
    im, d = canvas(W, H)
    im = soft_shadow(im, (12, 12, W - 12, H - 12), 50)
    d = ImageDraw.Draw(im)
    rrect(d, (12, 10, W - 12, H - 16), 50, rgb("fff0f5"), outline=rgb("ff8fb1"), width=8)
    text(d, (W / 2, H / 2 - 18), "Tatiana's", font(62, 700), rgb("e0567f"))
    text(d, (W / 2, H / 2 + 38), "(and Yoggi's, he insists)", font(26, 700, "Nunito"), rgb("b47a8c"))
    flower(d, 52, 52, 22, rgb("ff8fb1"))
    flower(d, W - 52, H - 62, 20, rgb("c49bff"))
    save(im, "her_place")


def menu_board():
    W, H = 640, 480
    im, d = canvas(W, H)
    wood(im, (0, 0, W, H), rgb("9b6a42"), r=26, plank_h=60, seed=11)
    d = ImageDraw.Draw(im)
    rrect(d, (26, 26, W - 26, H - 26), 14, rgb("2f3a36"))
    # chalk dust
    rnd = random.Random(4)
    for _ in range(500):
        x, y = rnd.uniform(30, W - 30), rnd.uniform(30, H - 30)
        d.point((S(x), S(y)), fill=(255, 255, 255, 40))
    chalk = rgb("f4f1e6")
    text(d, (W / 2, 78), "Menu", font(64, 700), chalk)
    heart(d, W / 2 + 112, 66, 14, rgb("ff8fb1"))
    items = [("Margherita", "8"), ("Pepperoni", "9"), ("Quattro Formaggi", "11"), ("Emergency Ham", "?"), ("Tiramisu", "5")]
    f = font(34, 600, "Nunito")
    for i, (n, p) in enumerate(items):
        y = 150 + i * 56
        text(d, (70, y), n, f, chalk, anchor="lm")
        text(d, (W - 70, y), p + "€", f, rgb("ffd45c"), anchor="rm")
        d.line([S(70 + d.textlength(n, font=f) / SS + 16), S(y + 8), S(W - 130), S(y + 8)], fill=chalk[:3] + (80,), width=S(2))
    save(im, "menu")


def popcorn_sign():
    W, H = 640, 200
    im, d = canvas(W, H)
    rrect(d, (6, 6, W - 6, H - 6), 40, rgb("fff3df"), outline=rgb("c9302c"), width=8)
    for i in range(40, W - 50, 48):
        d.rectangle([S(i), S(H - 46), S(i + 24), S(H - 14)], fill=rgb("e2483d"))
    rrect(d, (6, 6, W - 6, H - 6), 40, None, outline=rgb("c9302c"), width=8)
    text(d, (W / 2, 80), "Popcorn & Drinks", font(54, 700), rgb("d6362c"), stroke=3, stroke_fill=rgb("ffffff"))
    for x in (44, W - 44):
        for (dx, dy) in [(-14, 0), (14, -4), (0, -18), (-6, 14), (12, 14)]:
            d.ellipse([S(x + dx * 0.6 - 9), S(70 + dy * 0.6 - 9), S(x + dx * 0.6 + 9), S(70 + dy * 0.6 + 9)], fill=rgb("ffe9a0"), outline=rgb("e0b44a"), width=S(2))
    save(im, "popcorn")


def spa_plaque():
    W, H = 560, 170
    im, d = canvas(W, H)
    rrect(d, (8, 8, W - 8, H - 8), 70, rgb("e8f7f5"), outline=rgb("7cc7c0"), width=7)
    text(d, (W / 2, H / 2), "relax · breathe · nap", font(40, 600), rgb("3f8f88"))
    for x in (54, W - 54):
        d.ellipse([S(x - 26), S(H / 2 - 26), S(x + 26), S(H / 2 + 26)], fill=rgb("9fdc8a"))
        d.ellipse([S(x - 16), S(H / 2 - 16), S(x + 16), S(H / 2 + 16)], fill=rgb("dff5cf"))
    save(im, "spa")


def room_plaque(name, label, col):
    W, H = 420, 120
    im, d = canvas(W, H)
    wood(im, (6, 6, W - 6, H - 6), rgb("d8a06a"), r=40, plank_h=40, seed=hash(name) % 100)
    d = ImageDraw.Draw(im)
    rrect(d, (6, 6, W - 6, H - 6), 40, None, outline=rgb("7a4a28"), width=6)
    text(d, (W / 2, H / 2), label, font(46, 700), col, stroke=3, stroke_fill=rgb("fff3e6"))
    save(im, "room_" + name)


# ---------------------------------------------------------------------------
# Posters (2:3)
# ---------------------------------------------------------------------------

def poster_frame(im, d, W, H, title, tag, tcol, bg_tag):
    rrect(d, (0, 0, W, H), 0, None, outline=rgb("f2c14e"), width=14)
    rrect(d, (14, H - 150, W - 14, H - 14), 0, bg_tag)


def poster_horror():
    W, H = 512, 768
    im, d = canvas(W, H)
    for y in range(H):
        t = y / H
        c = (int(30 + 40 * t), int(20 + 10 * t), int(60 + 20 * t), 255)
        d.line([0, S(y), S(W), S(y)], fill=c)
    d.ellipse([S(300), S(70), S(440), S(210)], fill=rgb("f6f0c8"))
    d.ellipse([S(330), S(62), S(470), S(202)], fill=(42, 26, 72, 255))
    # House silhouette with glowing attic window
    d.polygon([(S(110), S(560)), (S(110), S(400)), (S(250), S(290)), (S(390), S(400)), (S(390), S(560))], fill=rgb("140d22"))
    d.polygon([(S(200), S(380)), (S(250), S(330)), (S(300), S(380))], fill=rgb("1d1330"))
    d.rectangle([S(232), S(352), S(268), S(388)], fill=rgb("ffce5a"))
    # Two eyes in the window
    d.ellipse([S(238), S(362), S(248), S(372)], fill=rgb("140d22"))
    d.ellipse([S(252), S(362), S(262), S(372)], fill=rgb("140d22"))
    for x in (150, 320):
        d.rectangle([S(x), S(430), S(x + 34), S(472)], fill=rgb("2a1f3d"))
    d.rectangle([S(0), S(560), S(W), S(H)], fill=rgb("0d0818"))
    for (x, y) in [(120, 160), (190, 120), (90, 230)]:
        d.polygon([(S(x - 18), S(y)), (S(x - 6), S(y - 6)), (S(x), S(y + 4)), (S(x + 6), S(y - 6)), (S(x + 18), S(y))], fill=rgb("0d0818"))
    text(d, (W / 2, 620), "THE THING\nIN THE ATTIC", font(52, 700), rgb("ff4b5c"), stroke=3, stroke_fill=rgb("2b0610"), spacing=4)
    text(d, (W / 2, 712), "it just wants to borrow a cup of sugar", font(20, 700, "Nunito"), rgb("d7c8f0"))
    rrect(d, (0, 0, W, H), 0, None, outline=rgb("f2c14e"), width=12)
    save(im, "poster_horror")


def poster_comedy():
    W, H = 512, 768
    im, d = canvas(W, H)
    for y in range(H):
        t = y / H
        d.line([0, S(y), S(W), S(y)], fill=(255, int(214 - 40 * t), int(90 - 30 * t), 255))
    # Sunburst
    for i in range(16):
        a0 = math.radians(i * 22.5)
        a1 = math.radians(i * 22.5 + 11)
        cx, cy = W / 2, 330
        d.polygon([(S(cx), S(cy)), (S(cx + math.cos(a0) * 600), S(cy + math.sin(a0) * 600)),
                   (S(cx + math.cos(a1) * 600), S(cy + math.sin(a1) * 600))], fill=(255, 240, 160, 120))
    # A pizza slice wearing a police hat and sunglasses
    pizza_slice(d, W / 2, 360, 300, rot=180)
    d.rounded_rectangle([S(W / 2 - 100), S(190), S(W / 2 + 100), S(240)], radius=S(16), fill=rgb("26407a"))
    d.rectangle([S(W / 2 - 120), S(232), S(W / 2 + 120), S(250)], fill=rgb("1a2c55"))
    star(d, W / 2, 214, 18, rgb("ffd45c"))
    d.rounded_rectangle([S(W / 2 - 92), S(300), S(W / 2 - 14), S(340)], radius=S(12), fill=rgb("1a1a1a"))
    d.rounded_rectangle([S(W / 2 + 14), S(300), S(W / 2 + 92), S(340)], radius=S(12), fill=rgb("1a1a1a"))
    d.line([S(W / 2 - 14), S(312), S(W / 2 + 14), S(312)], fill=rgb("1a1a1a"), width=S(6))
    d.arc([S(W / 2 - 50), S(350), S(W / 2 + 50), S(420)], 20, 160, fill=rgb("8a2a1a"), width=S(7))
    text(d, (W / 2, 610), "PIZZA COPS 3", font(66, 700), rgb("ffffff"), stroke=5, stroke_fill=rgb("c9302c"),
         shadow=(0, 6, rgb("8a2a1a", 160)))
    text(d, (W / 2, 676), "this time it's crust-onal", font(24, 700, "Nunito"), rgb("7a3a1a"))
    rrect(d, (0, 0, W, H), 0, None, outline=rgb("f2c14e"), width=12)
    save(im, "poster_comedy")


def poster_drama():
    W, H = 512, 768
    im, d = canvas(W, H)
    for y in range(H):
        t = y / H
        c = (int(255 - 60 * t), int(170 - 60 * t), int(140 + 20 * t), 255)
        d.line([0, S(y), S(W), S(y)], fill=c)
    d.ellipse([S(W / 2 - 90), S(330), S(W / 2 + 90), S(510)], fill=rgb("ffe08a"))
    d.rectangle([0, S(430), S(W), S(H)], fill=rgb("5a6fb0"))
    for k in range(6):
        y = 450 + k * 22
        d.line([S(W / 2 - 80 + k * 6), S(y), S(W / 2 + 80 - k * 6), S(y)], fill=rgb("ffe08a", 160 - k * 24), width=S(4))
    # Pier, two people and a dog
    d.rectangle([S(0), S(500), S(300), S(516)], fill=rgb("3b2a3a"))
    for x in range(20, 300, 60):
        d.rectangle([S(x), S(516), S(x + 10), S(560)], fill=rgb("3b2a3a"))
    for (x, h) in [(190, 92), (226, 84)]:
        d.ellipse([S(x - 14), S(500 - h - 28), S(x + 14), S(500 - h)], fill=rgb("3b2a3a"))
        d.rounded_rectangle([S(x - 16), S(500 - h), S(x + 16), S(500)], radius=S(8), fill=rgb("3b2a3a"))
    d.ellipse([S(258), S(476), S(296), S(500)], fill=rgb("3b2a3a"))
    d.ellipse([S(284), S(462), S(304), S(482)], fill=rgb("3b2a3a"))
    heart(d, 208, 360, 20, rgb("ff6f91"))
    text(d, (W / 2, 612), "A DOG NAMED\nSUNDAY", font(50, 700), rgb("ffffff"), stroke=3, stroke_fill=rgb("3b2a3a"), spacing=4)
    text(d, (W / 2, 704), "bring tissues. bring two.", font(22, 700, "Nunito"), rgb("ffe9d6"))
    rrect(d, (0, 0, W, H), 0, None, outline=rgb("f2c14e"), width=12)
    save(im, "poster_drama")


if __name__ == "__main__":
    pizzeria(); cinema(); hotel(); oasis_arrow(); garden(); house_plaque(); her_plaque()
    menu_board(); popcorn_sign(); spa_plaque()
    room_plaque("living", "Living Room", rgb("8a4a2a"))
    room_plaque("bedroom", "Bedroom", rgb("6a4a9a"))
    room_plaque("office", "Office", rgb("2f6f78"))
    poster_horror(); poster_comedy(); poster_drama()

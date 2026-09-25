"""Draws the app icon: a white wallet with green bills and a gold clasp, on deep blue.

Run from the repo root, then let flutter_launcher_icons generate the platform sizes:
    python tool/make_app_icon.py
    dart run flutter_launcher_icons

Writes:
    assets/icon/app_icon.png             full icon (iOS, macOS, web, Android legacy)
    assets/icon/app_icon_foreground.png  wallet only, transparent, inside Android's adaptive safe zone
    assets/icon/app_icon_background.png  background only, for Android adaptive icons
    windows/runner/resources/app_icon.ico  every Windows size, each rendered separately
"""
from PIL import Image, ImageDraw, ImageFilter, ImageFont

K = 4                      # supersampling factor, everything is drawn 4x and scaled down
S = 1024 * K               # working canvas size

# The wallet artwork spans roughly y 235..724, so this moves it to the optical center
CENTER_OFFSET_Y = 30
# NOTE: flutter_launcher_icons already insets the Android foreground by 16%, which on its own
# makes the wallet the same size as on iOS. This shrinks it a little more so the bills and clasp
# stay inside launchers that mask the icon to a circle
ADAPTIVE_SCALE = 0.92
# Windows icons are tiny in the taskbar, so they use a tighter crop around the wallet
WINDOWS_CROP = 150


def s(v):
    """Design units (1024 canvas) to working pixels."""
    return int(round(v * K))


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(len(a)))


def hex_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def vertical_gradient(size, top, bottom):
    w, h = size
    col = Image.new("RGB", (1, h))
    for y in range(h):
        col.putpixel((0, y), lerp(top, bottom, y / max(1, h - 1)))
    return col.resize((w, h))


def blank():
    return Image.new("RGBA", (S, S), (0, 0, 0, 0))


def gradient_shape(box, radius, top, bottom):
    """A rounded rect filled with a vertical gradient, on a transparent full-size layer."""
    x0, y0, x1, y1 = box
    layer = blank()
    fill = vertical_gradient((x1 - x0, y1 - y0), top, bottom).convert("RGBA")
    mask = Image.new("L", (x1 - x0, y1 - y0), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, x1 - x0 - 1, y1 - y0 - 1), radius=radius, fill=255)
    layer.paste(fill, (x0, y0), mask)
    return layer


def shadow(box, radius, blur, offset, alpha):
    layer = blank()
    x0, y0, x1, y1 = box
    ImageDraw.Draw(layer).rounded_rectangle(
        (x0 + offset[0], y0 + offset[1], x1 + offset[0], y1 + offset[1]), radius=radius, fill=(4, 12, 40, alpha))
    return layer.filter(ImageFilter.GaussianBlur(blur))


def bill(center, w, h, angle, top, bottom, edge):
    """A banknote drawn flat, then rotated around its center."""
    note = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    fill = vertical_gradient((w, h), top, bottom).convert("RGBA")
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, w - 1, h - 1), radius=s(18), fill=255)
    note.paste(fill, (0, 0), mask)
    d = ImageDraw.Draw(note)
    inset = s(22)
    d.rounded_rectangle((inset, inset, w - inset, h - inset), radius=s(10), outline=edge, width=s(6))
    r = s(34)
    d.ellipse((w // 2 - r, s(48) - r // 2, w // 2 + r, s(48) + r + r // 2), outline=edge, width=s(6))
    note = note.rotate(angle, resample=Image.BICUBIC, expand=True)
    layer = blank()
    layer.alpha_composite(note, (center[0] - note.width // 2, center[1] - note.height // 2))
    return layer


def draw_background():
    img = vertical_gradient((S, S), hex_rgb("1E63C8"), hex_rgb("0A1F5C")).convert("RGBA")
    glow = blank()
    ImageDraw.Draw(glow).ellipse((s(170), s(150), s(854), s(834)), fill=(120, 170, 255, 70))
    img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(s(110))))
    return img


def draw_wallet():
    """The wallet with its shadows, on a transparent layer."""
    img = blank()

    # Bills peeking out of the wallet
    img.alpha_composite(bill((s(470), s(372)), s(400), s(200), 9,
                             hex_rgb("81C784"), hex_rgb("4CAF50"), (232, 245, 233, 200)))
    img.alpha_composite(bill((s(560), s(352)), s(400), s(200), -6,
                             hex_rgb("66BB6A"), hex_rgb("2E7D32"), (232, 245, 233, 220)))

    # Wallet body
    body = (s(262), s(412), s(762), s(724))
    img.alpha_composite(shadow(body, s(64), s(28), (0, s(22)), 150))
    img.alpha_composite(gradient_shape(body, s(64), hex_rgb("FFFFFF"), hex_rgb("DCE5F3")))

    # Stitched lip along the top of the wallet
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((s(262), s(412), s(762), s(470)), radius=s(64), fill=(236, 241, 250, 255))
    d.rectangle((s(262), s(445), s(762), s(470)), fill=(236, 241, 250, 255))
    for x in range(s(310), s(720), s(34)):
        d.line((x, s(452), x + s(16), s(452)), fill=(170, 186, 214, 255), width=s(5))

    # Clasp tab with a gold snap
    tab = (s(592), s(508), s(800), s(628))
    img.alpha_composite(shadow(tab, s(60), s(14), (-s(6), s(10)), 110))
    img.alpha_composite(gradient_shape(tab, s(60), hex_rgb("C9D6EC"), hex_rgb("A9BBDA")))

    cx, cy, r = s(704), s(568), s(40)
    img.alpha_composite(gradient_shape((cx - r, cy - r, cx + r, cy + r), r, hex_rgb("FFE082"), hex_rgb("FFB300")))
    d = ImageDraw.Draw(img)
    d.ellipse((cx - r, cy - r, cx + r, cy + r), outline=(230, 150, 0, 255), width=s(5))
    font = ImageFont.truetype("C:/Windows/Fonts/segoeuib.ttf", s(58))
    d.text((cx, cy + s(2)), "$", font=font, fill=(173, 104, 0, 255), anchor="mm")
    return img


def place(layer, scale):
    """Scales the artwork around the canvas center and moves it to the optical center."""
    size = int(S * scale)
    scaled = layer.resize((size, size), Image.LANCZOS)
    out = blank()
    out.alpha_composite(scaled, ((S - size) // 2, (S - size) // 2 + s(CENTER_OFFSET_Y * scale)))
    return out


def final(img):
    return img.resize((1024, 1024), Image.LANCZOS)


background = draw_background()
wallet = draw_wallet()

full = background.copy()
full.alpha_composite(place(wallet, 1.0))
final(full).convert("RGB").save("assets/icon/app_icon.png", optimize=True)

final(place(wallet, ADAPTIVE_SCALE)).save("assets/icon/app_icon_foreground.png", optimize=True)
final(background).convert("RGB").save("assets/icon/app_icon_background.png", optimize=True)

# NOTE: Small Windows sizes (taskbar, Explorer) get their own downscale instead of
# Windows shrinking the 256px one on the fly, which looks blurry
c = s(WINDOWS_CROP)
final(full.crop((c, c, S - c, S - c))).save(
    "windows/runner/resources/app_icon.ico",
    sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
)
print("Icons written. Now run: dart run flutter_launcher_icons")

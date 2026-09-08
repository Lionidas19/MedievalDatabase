"""Draws the application icons.

    python tools/make_icons.py

The web project shipped with Flutter's own logo in `web/icons/`, which is fine
for a scaffold and wrong for something a researcher installs — it would sit on
their desktop looking like a Flutter demo.

The mark is the reverse of a long cross penny: a cross whose arms run to the
edge of the coin, quartering it, with three pellets in each quarter. That is
the coin these records are counted in. Edward I's recoinage of 1279 falls in
the middle of the period covered here, and the Henry III long cross pennies
before it circulated throughout — so it is the one image that is both literally
correct and legible at sixteen pixels, which a castle outline is not.

Drawn at four times the final size and reduced, because PIL has no
anti-aliasing of its own and a hand-drawn circle without it is a staircase.
"""
import os

from PIL import Image, ImageDraw

_REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WEB = os.path.join(_REPO_ROOT, "app", "web")

# app/lib/theme.dart: the Parchment palette's seed and its lightest surface.
LEATHER = (0x7A, 0x52, 0x30)
PARCHMENT = (0xFB, 0xF6, 0xEC)

SUPERSAMPLE = 4


def draw(size, coin_fraction):
    """One icon: a parchment ground with the coin centred on it.

    `coin_fraction` is how much of the width the coin takes. A maskable icon
    can be cropped to a circle of 80% of the canvas by the launcher, so its
    coin has to sit well inside that; an ordinary icon can use the room.
    """
    px = size * SUPERSAMPLE
    img = Image.new("RGBA", (px, px), PARCHMENT + (255,))
    centre = px / 2
    radius = px * coin_fraction / 2

    coin = ImageDraw.Draw(img)
    coin.ellipse(
        [centre - radius, centre - radius, centre + radius, centre + radius],
        fill=LEATHER + (255,),
    )

    # The cross and pellets are drawn onto their own layer and then stencilled
    # through a disc, so the cross arms stop exactly at the coin's edge rather
    # than running out across the ground.
    device = Image.new("RGBA", (px, px), (0, 0, 0, 0))
    pen = ImageDraw.Draw(device)

    # Narrow. Wide arms cut the coin into four loose wedges and it stops
    # reading as a disc at all; at a tenth of the radius the metal still
    # dominates and the cross reads as struck into it.
    arm = radius * 0.10          # half the width of a cross arm
    pen.rectangle([centre - arm, 0, centre + arm, px], fill=PARCHMENT + (255,))
    pen.rectangle([0, centre - arm, px, centre + arm], fill=PARCHMENT + (255,))

    # Three pellets per quarter, in a triangle pointing at the centre, which
    # is how they sit on the coin.
    pellet = radius * 0.085
    near, far = radius * 0.40, radius * 0.63
    for sx in (-1, 1):
        for sy in (-1, 1):
            for dx, dy in ((near, near), (far, near), (near, far)):
                x, y = centre + sx * dx, centre + sy * dy
                pen.ellipse(
                    [x - pellet, y - pellet, x + pellet, y + pellet],
                    fill=PARCHMENT + (255,),
                )

    # A rim, drawn over the cross ends so the four quarters are visibly one
    # coin. The arms still reach it, which is what makes the cross a long one.
    rim = radius * 0.07
    pen.ellipse(
        [centre - radius + rim / 2, centre - radius + rim / 2,
         centre + radius - rim / 2, centre + radius - rim / 2],
        outline=LEATHER + (255,), width=int(round(rim)),
    )

    disc = Image.new("L", (px, px), 0)
    ImageDraw.Draw(disc).ellipse(
        [centre - radius, centre - radius, centre + radius, centre + radius],
        fill=255,
    )
    img.paste(device, (0, 0), Image.composite(
        device.split()[3], Image.new("L", (px, px), 0), disc))

    return img.resize((size, size), Image.LANCZOS)


def write(name, size, coin_fraction):
    path = os.path.join(WEB, name)
    draw(size, coin_fraction).save(path)
    print("  {:<34} {}x{}".format(name, size, size))


if __name__ == "__main__":
    print("writing icons into app/web/")
    # 0.78 leaves a little parchment showing as a border. 0.56 keeps the whole
    # coin inside a maskable icon's safe zone even when a launcher crops it
    # hard to a circle.
    write("icons/Icon-192.png", 192, 0.78)
    write("icons/Icon-512.png", 512, 0.78)
    write("icons/Icon-maskable-192.png", 192, 0.56)
    write("icons/Icon-maskable-512.png", 512, 0.56)
    # The browser tab. Bigger than Flutter's 16px default so it survives on a
    # high-resolution display, and the coin takes almost the whole square
    # because at this size a border is just lost pixels.
    write("favicon.png", 64, 0.92)

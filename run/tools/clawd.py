#!/usr/bin/env python3
"""Dibuja a Clawd desde su cuadrícula de píxeles, tomada de la imagen que pasó el
usuario: 11 columnas por 8 filas, naranja con ojos negros. Se dibuja aquí y no se
genera para que sea idéntico en todos los cuadros de la animación."""
from PIL import Image, ImageFilter

GRID = [
    ".XXXXXXXXX.",
    ".XXXXXXXXX.",
    "XXEXXXXXEXX",
    "XXXXXXXXXXX",
    ".XXXXXXXXX.",
    ".XXXXXXXXX.",
    ".X.X...X.X.",
    ".X.X...X.X.",
]
ORANGE = (217, 119, 87, 255)
EYE = (0, 0, 0, 255)
OUTLINE = (84, 50, 34, 255)  # Mismo café del contorno de BeCa.
SUPER = 8  # Se dibuja grande para que al rotar y reducir los bordes queden limpios.


def clawd(cell_px: float = 4.0, angle: float = 0.0, outline_px: float = 1.6) -> Image.Image:
    """Clawd girado `angle` grados, con cuadrícula de `cell_px` píxeles finales."""
    unit = round(cell_px * SUPER)
    border = round(outline_px * SUPER)
    w, h = len(GRID[0]) * unit, len(GRID) * unit
    pad = border + unit
    body = Image.new("RGBA", (w + 2 * pad, h + 2 * pad), (0, 0, 0, 0))
    px = body.load()
    for r, row in enumerate(GRID):
        for c, ch in enumerate(row):
            if ch == ".":
                continue
            color = EYE if ch == "E" else ORANGE
            for y in range(pad + r * unit, pad + (r + 1) * unit):
                for x in range(pad + c * unit, pad + (c + 1) * unit):
                    px[x, y] = color
    mask = body.getchannel("A").filter(ImageFilter.MaxFilter(2 * (border // 2) + 1))
    for _ in range(2):
        mask = mask.filter(ImageFilter.MaxFilter(2 * (border // 4) + 1))
    art = Image.new("RGBA", body.size, OUTLINE)
    art.putalpha(mask)
    art.alpha_composite(body)
    if angle:
        art = art.rotate(angle, resample=Image.Resampling.BICUBIC, expand=True)
    size = (max(1, art.width // SUPER), max(1, art.height // SUPER))
    art = art.resize(size, Image.Resampling.LANCZOS)
    return art.crop(art.getchannel("A").getbbox())


if __name__ == "__main__":
    import sys
    out = sys.argv[1]
    sheet = Image.new("RGBA", (420, 90), (235, 235, 240, 255))
    x = 8
    for a in (0, 20, 45, 90, 135, 180):
        c = clawd(4.0, a)
        sheet.alpha_composite(c, (x, 45 - c.height // 2))
        x += c.width + 10
    sheet = sheet.resize((sheet.width * 2, sheet.height * 2), Image.Resampling.NEAREST)
    sheet.save(out)

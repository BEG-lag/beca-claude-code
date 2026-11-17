#!/usr/bin/env python3
"""Recorta del sprite sheet solo los cuadros que usa la app, una tira por clip.

Evita tener en memoria el sheet completo: 1536x1872 RGBA ocupa 11 MB decodificado
aunque la app solo muestre un clip a la vez.
"""
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
CELL_WIDTH, CELL_HEIGHT = 192, 208
CLIPS = {"idle": (0, 6), "waving": (3, 4), "jumping": (4, 5), "failed": (5, 8),
         "waiting": (6, 6), "running": (7, 6), "review": (8, 6)}

source = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "run/final/spritesheet.png"
sheet = Image.open(source).convert("RGBA")
output = ROOT / "app/clips"
output.mkdir(exist_ok=True)
for name, (row, frames) in CLIPS.items():
    box = (0, row * CELL_HEIGHT, frames * CELL_WIDTH, (row + 1) * CELL_HEIGHT)
    sheet.crop(box).save(output / f"{name}.png", optimize=True)
    print(name, frames, (output / f"{name}.png").stat().st_size // 1024, "KB")

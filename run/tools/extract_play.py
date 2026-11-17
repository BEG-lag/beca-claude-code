#!/usr/bin/env python3
"""Saca las poses de BeCa jugando de la tira generada, con la misma limpieza de
fondo que el resto de las animaciones, y las deja a escala final en una tira."""
import subprocess
import sys
from pathlib import Path
from PIL import Image

sys.path.insert(0, str(Path(__file__).parent))
from normalize_rows import SKILL_SCRIPTS, head_width, is_coat  # noqa: E402
from extract_strip_frames import (  # noqa: E402
    component_frame_groups, component_group_image, parse_hex_color, remove_chroma_background)

CELL_W, CELL_H = 192, 208
ROOT = Path(__file__).resolve().parents[2]
JUEGO = ROOT / "arte-gato/juego"
source = sys.argv[1] if len(sys.argv) > 1 else "play-a.png"
head_px = float(sys.argv[2]) if len(sys.argv) > 2 else 110.0

with Image.open(JUEGO / source) as opened:
    strip = remove_chroma_background(opened, parse_hex_color("#00FF00"), 96.0)
groups = component_frame_groups(strip, 8)
if groups is None:
    raise SystemExit("no encontré 8 poses")
poses = [component_group_image(strip, group, padding=0) for group in groups]
scale = head_px / head_width(poses[2], is_coat)
# Cada pose se apoya en la orilla derecha y en el piso de la celda: la izquierda
# queda libre para Clawd.
strip_out = Image.new("RGBA", (CELL_W * len(poses), CELL_H), (0, 0, 0, 0))
for i, pose in enumerate(poses):
    size = (round(pose.width * scale), round(pose.height * scale))
    small = pose.resize(size, Image.Resampling.LANCZOS)
    strip_out.alpha_composite(small, (i * CELL_W + CELL_W - 3 - small.width, 204 - small.height))
    print(i, "final", small.size)
strip_out.save(JUEGO / "poses-strip.png")
subprocess.run(
    [sys.executable, str(SKILL_SCRIPTS / "despill_chroma_edges.py"),
     str(JUEGO / "poses-strip.png"), "--output", str(JUEGO / "poses-limpias.png"),
     "--json-out", str(JUEGO / "despill.json"), "--chroma-key", "#00FF00"],
    check=True, stdout=subprocess.DEVNULL)
print("escala", round(scale, 4))

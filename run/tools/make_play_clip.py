#!/usr/bin/env python3
"""Arma app/clips/play.png: BeCa juega con Clawd como con una bola de estambre.

Las poses de BeCa son las generadas; Clawd se compone encima o debajo cuadro por
cuadro, así su forma no cambia y su movimiento queda bajo control. Imprime la
lista de duraciones que va en Clips.play de app/main.swift."""
import sys
from pathlib import Path
from PIL import Image

sys.path.insert(0, str(Path(__file__).parent))
from clawd import clawd  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
W, H = 192, 208
GROUND = 204
CLAWD_PX = 3.6
G = None  # Clawd apoyado en el piso.

# pose, x del centro de Clawd, y del centro (G = piso), giro, capa, duración, aplastado.
# Giro positivo es antihorario: rodar hacia la izquierda. "abajo" lo tapa la pata.
TIMELINE = [
    # Clawd entra caminando y BeCa lo acecha moviendo la cadera.
    (0, -16, G, 7, "arriba", .12, 1),
    (0, -5, G, -7, "arriba", .12, 1),
    (1, 6, G, 7, "arriba", .12, 1),
    (1, 16, G, -7, "arriba", .12, 1),
    (0, 19, G, 0, "arriba", .16, 1),
    (1, 19, G, 0, "arriba", .16, 1),
    # Manotazo: sale rodando y rebota contra la orilla.
    (2, 19, G, 0, "arriba", .22, 1),
    (3, 22, G, 0, "abajo", .08, .86),
    (3, 12, 166, 70, "arriba", .08, 1),
    (3, 12, G, 140, "arriba", .09, 1),
    # Regresa rodando hasta las patas.
    (0, 20, G, 80, "arriba", .09, 1),
    (1, 28, G, 20, "arriba", .10, 1),
    # Se le echa encima y Clawd sale disparado hacia arriba.
    (5, 38, G, 0, "abajo", .10, .8),
    (5, 38, G, 0, "abajo", .16, .7),
    (4, 30, 120, -70, "arriba", .08, 1),
    (4, 30, 70, -150, "arriba", .09, 1),
    (4, 42, 34, -230, "arriba", .11, 1),
    (4, 58, 36, -300, "arriba", .10, 1),
    # BeCa cae de espaldas y lo hace malabares con las patas.
    (6, 92, 50, -350, "arriba", .10, 1),
    (6, 122, 66, -360, "arriba", .11, 1),
    (7, 150, 72, -345, "arriba", .11, 1),
    (6, 122, 60, -375, "arriba", .11, 1),
    (7, 150, 70, -345, "arriba", .11, 1),
    (6, 122, 56, -375, "arriba", .11, 1),
    (7, 150, 56, -340, "arriba", .09, 1),
    # La patada final lo manda volando; BeCa vuelve a agacharse a mirarlo.
    (7, 122, 28, 30, "arriba", .08, 1),
    (0, 88, 24, 95, "arriba", .08, 1),
    (0, 54, 40, 165, "arriba", .08, 1),
    (0, 30, 84, 235, "arriba", .08, 1),
    (1, 16, 140, 305, "arriba", .08, 1),
    (1, 12, G, 360, "arriba", .10, .8),
    (0, 10, 168, 0, "arriba", .10, 1),
    # BeCa se sienta, le dice adiós con la pata y Clawd se va.
    (2, 6, G, 7, "arriba", .13, 1),
    (2, -8, G, -7, "arriba", .13, 1),
    (2, -24, G, 7, "arriba", .13, 1),
]


def frame(sheet: Image.Image, spec) -> Image.Image:
    pose, x, y, angle, layer, _, squash = spec
    cat = sheet.crop((pose * W, 0, (pose + 1) * W, H))
    toy = clawd(CLAWD_PX, angle % 360)
    if squash != 1:
        toy = toy.resize((round(toy.width * (2 - squash)), round(toy.height * squash)), Image.Resampling.LANCZOS)
    top = GROUND - toy.height if y is None else round(y - toy.height / 2)
    toy_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    toy_layer.paste(toy, (round(x - toy.width / 2), top))
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    for part in ((cat, toy_layer) if layer == "arriba" else (toy_layer, cat)):
        out.alpha_composite(part)
    return out


def main() -> None:
    sheet = Image.open(ROOT / "arte-gato/juego/poses-limpias.png").convert("RGBA")
    frames = [frame(sheet, spec) for spec in TIMELINE]
    strip = Image.new("RGBA", (W * len(frames), H), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        strip.paste(f, (i * W, 0))
    out = ROOT / "app/clips/play.png"
    strip.save(out, optimize=True)

    qa = ROOT / "arte-gato/juego"
    cols = 7
    rows = -(-len(frames) // cols)
    contact = Image.new("RGBA", (cols * W, rows * H), (235, 235, 240, 255))
    for i, f in enumerate(frames):
        contact.alpha_composite(f, ((i % cols) * W, (i // cols) * H))
    contact.convert("RGB").resize((cols * W * 3 // 4, rows * H * 3 // 4), Image.Resampling.LANCZOS).save(qa / "play-contacto.png")
    gif = []
    for f in frames:
        bg = Image.new("RGBA", (W, H), (235, 235, 240, 255))
        bg.alpha_composite(f)
        gif.append(bg.convert("RGB").quantize(128))
    gif[0].save(qa / "play.gif", save_all=True, append_images=gif[1:], loop=0,
                duration=[round(s[5] * 1000) for s in TIMELINE])

    durations = ", ".join(f"{s[5]:.2f}" for s in TIMELINE)
    print(f"{len(frames)} cuadros, {sum(s[5] for s in TIMELINE):.2f} s, {out.stat().st_size // 1024} KB")
    print(f"durations: [{durations}]")


if __name__ == "__main__":
    main()

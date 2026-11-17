#!/usr/bin/env python3
"""Refit generated strip poses with one pet scale across every row.

The bundled extractor fits each row to its own viewport, so a row with real
vertical motion comes out smaller than idle. This wrapper reuses the bundled
chroma removal and component grouping, then applies one head-based scale to all
rows, a shared ground line, and a uniform compression of the jump displacement.
It only moves and resamples generated pixels; it never draws anything.
"""
from __future__ import annotations

import argparse
import json
import os
import statistics
import sys
from pathlib import Path

from PIL import Image

# Scripts del skill hatch-pet, que no viene en este repo. Se puede cambiar con HATCH_PET_SCRIPTS.
SKILL_SCRIPTS = Path(os.environ.get("HATCH_PET_SCRIPTS", Path.home() / ".claude/skills/hatch-pet/scripts"))
sys.path.insert(0, str(SKILL_SCRIPTS))
from extract_strip_frames import (  # noqa: E402
    CELL_HEIGHT,
    CELL_WIDTH,
    ROW_FRAME_COUNTS,
    component_bounds,
    component_frame_groups,
    component_group_image,
    parse_hex_color,
    remove_chroma_background,
)

PLANTED = {"idle", "waving", "failed", "waiting", "running", "review"}
SIDE_VIEW = {"running-right", "running-left"}
MARGIN = 3
# Pose with the arms down and the head frontal, so a raised paw is not measured as head.
HEAD_REFERENCE_FRAME = {
    "idle": 0,
    "waving": 0,
    "jumping": 0,
    "failed": 0,
    "waiting": 2,
    "running": 5,
    "review": 4,
}


def is_pink(red: int, green: int, blue: int) -> bool:
    return red > 225 and 140 < green < 225 and 150 < blue < 225 and red - green > 25


def is_coat(red: int, green: int, blue: int) -> bool:
    """Pelaje crema o durazno; deja fuera contorno, bigotes blancos y fondo."""
    return red > 190 and green > 130 and blue < 205 and red - blue > 35


HEAD_COLORS = {"pink": is_pink, "coat": is_coat}


def head_width(pose: Image.Image, is_head) -> int:
    """Widest head-colored span in the upper half of a pose."""
    pixels = pose.load()
    best = 0
    for y in range(pose.height // 2):
        xs = [
            x
            for x in range(pose.width)
            if pixels[x, y][3] > 200 and is_head(*pixels[x, y][:3])
        ]
        if len(xs) > 8:
            best = max(best, xs[-1] - xs[0] + 1)
    return best


def lower_center_x(pose: Image.Image) -> float:
    """Mean x of the bottom band, which is the feet on a planted pose."""
    alpha = pose.getchannel("A")
    box = alpha.point(lambda v: 255 if v > 16 else 0).getbbox()
    band_top = box[3] - max(4, round((box[3] - box[1]) * 0.10))
    pixels = alpha.load()
    xs = [x for y in range(band_top, box[3]) for x in range(pose.width) if pixels[x, y] > 16]
    return sum(xs) / len(xs)


def centroid_x(pose: Image.Image) -> float:
    alpha = pose.getchannel("A")
    pixels = alpha.load()
    total = weighted = 0
    for y in range(pose.height):
        for x in range(pose.width):
            if pixels[x, y] > 16:
                total += 1
                weighted += x
    return weighted / total


def load_poses(path: Path, count: int, key: tuple[int, int, int], threshold: float):
    with Image.open(path) as opened:
        strip = remove_chroma_background(opened, key, threshold)
    groups = component_frame_groups(strip, count)
    if groups is None:
        raise SystemExit(f"could not find {count} poses in {path}")
    return [
        (component_group_image(strip, group, padding=0), component_bounds(group))
        for group in groups
    ]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--decoded-dir", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--chroma-key", default="#00FF00")
    parser.add_argument("--key-threshold", type=float, default=96.0)
    parser.add_argument("--head-px", type=float, default=94.0)
    parser.add_argument("--baseline", type=int, default=204)
    parser.add_argument("--jump-peak-px", type=float, default=28.0)
    parser.add_argument("--side-height-ratio", type=float, default=1.0)
    parser.add_argument("--head-color", choices=sorted(HEAD_COLORS), default="pink")
    parser.add_argument("--states", default="all", help="Lista separada por comas.")
    args = parser.parse_args()

    decoded = Path(args.decoded_dir).expanduser().resolve()
    output = Path(args.output_dir).expanduser().resolve()
    key = parse_hex_color(args.chroma_key)

    wanted = list(ROW_FRAME_COUNTS) if args.states == "all" else args.states.split(",")
    poses = {
        state: load_poses(decoded / f"{state}.png", ROW_FRAME_COUNTS[state], key, args.key_threshold)
        for state in wanted
    }
    is_head = HEAD_COLORS[args.head_color]

    scales: dict[str, float] = {}
    for state, row in poses.items():
        if state not in SIDE_VIEW:
            reference = row[HEAD_REFERENCE_FRAME[state]][0]
            scales[state] = args.head_px / head_width(reference, is_head)

    idle_height = statistics.median(box[3] - box[1] for _, box in poses["idle"]) * scales["idle"]
    for state in SIDE_VIEW & set(poses):
        side_height = statistics.median(box[3] - box[1] for _, box in poses[state])
        scales[state] = idle_height * args.side_height_ratio / side_height

    rows = []
    report = {}
    for state, row in poses.items():
        scale = scales[state]
        ground = max(box[3] for _, box in row)
        peak = max(ground - box[3] for _, box in row)
        state_dir = output / state
        state_dir.mkdir(parents=True, exist_ok=True)
        files = []
        extents = []
        for index, (pose, box) in enumerate(row):
            anchor = lower_center_x(pose) if state in PLANTED else centroid_x(pose)
            width = max(1, round(pose.width * scale))
            height = max(1, round(pose.height * scale))
            resized = pose.resize((width, height), Image.Resampling.LANCZOS)
            lift = 0.0
            if state == "jumping" and peak > 0:
                lift = (ground - box[3]) / peak * args.jump_peak_px
            left = round(CELL_WIDTH / 2 - anchor * scale)
            left = min(max(left, MARGIN), CELL_WIDTH - MARGIN - width)
            top = round(args.baseline - lift - height)
            if top < MARGIN:
                raise SystemExit(f"{state}[{index}] clips the top by {MARGIN - top}px")
            if width > CELL_WIDTH - 2 * MARGIN:
                raise SystemExit(f"{state}[{index}] is {width}px wide")
            cell = Image.new("RGBA", (CELL_WIDTH, CELL_HEIGHT), (0, 0, 0, 0))
            cell.alpha_composite(resized, (left, top))
            path = state_dir / f"{index:02d}.png"
            cell.save(path)
            files.append(str(path))
            extents.append([left, top, left + width, top + height])
        rows.append({"state": state, "frames": files, "method": "components"})
        report[state] = {"scale": round(scale, 4), "extents": extents}

    (output / "frames-manifest.json").write_text(
        json.dumps(
            {
                "ok": True,
                "chroma_key": {
                    "hex": args.chroma_key.upper(),
                    "rgb": list(key),
                    "threshold": args.key_threshold,
                },
                "rows": rows,
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    (output / "normalization-report.json").write_text(
        json.dumps(report, indent=2) + "\n", encoding="utf-8"
    )
    for state, entry in report.items():
        tops = [e[1] for e in entry["extents"]]
        lefts = [e[0] for e in entry["extents"]]
        rights = [e[2] for e in entry["extents"]]
        print(f"{state:14} scale={entry['scale']:.3f} top={min(tops):3d} x=[{min(lefts)},{max(rights)}]")


if __name__ == "__main__":
    main()

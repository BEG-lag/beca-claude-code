#!/usr/bin/env python3
"""Resume una o dos corridas de bench/medir.sh. Uso: resumen.py <etiqueta> [<etiqueta>]"""
import csv, re, statistics, sys
from pathlib import Path

ROOT = Path(__file__).parent / "resultados"

def slope(xs, ys):
    mx, my = statistics.fmean(xs), statistics.fmean(ys)
    den = sum((x - mx) ** 2 for x in xs)
    return sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / den if den else 0.0

def scenario(label, name):
    rows = list(csv.DictReader((ROOT / label / f"{name}.csv").open()))
    t = [float(r["t"]) for r in rows]
    fp = [float(r["footprint_mb"]) for r in rows]
    cpu = [float(r["cpu_pct"]) for r in rows]
    wk = [float(r["wakeups_s"]) for r in rows]
    return {
        "mem_ini": fp[0], "mem_fin": fp[-1], "mem_max": max(fp),
        "pendiente_mb_min": slope(t, fp) * 60,
        "cpu_media": statistics.fmean(cpu), "cpu_max": max(cpu),
        "despertares_s": statistics.fmean(wk),
        "hilos": rows[-1]["threads"],
    }

def windowserver(label):
    def seconds(v):
        m, s = v.split(":")
        return int(m) * 60 + float(s)
    marks = {}
    for line in (ROOT / label / "windowserver.txt").read_text().splitlines():
        name, kind, value = line.split()
        marks.setdefault(name, {})[kind] = seconds(value)
    return {k: 100 * (v["ws_fin"] - v["ws_inicio"]) / 60 for k, v in marks.items() if len(v) == 2}

for label in sys.argv[1:]:
    print(f"== {label}")
    print(f"{'escenario':9} {'mem ini':>8} {'mem fin':>8} {'mem max':>8} {'MB/min':>7} {'CPU %':>7} {'CPU max':>8} {'despert/s':>9} hilos")
    for name in ("quieta", "reposo", "animada", "rafaga", "oculta"):
        if not (ROOT / label / f"{name}.csv").exists():
            continue
        s = scenario(label, name)
        print(f"{name:9} {s['mem_ini']:8.2f} {s['mem_fin']:8.2f} {s['mem_max']:8.2f} {s['pendiente_mb_min']:7.3f} "
              f"{s['cpu_media']:7.3f} {s['cpu_max']:8.2f} {s['despertares_s']:9.2f} {s['hilos']}")
    print("WindowServer % CPU:", {k: round(v, 2) for k, v in windowserver(label).items()})
    print((ROOT / label / "cerrada.txt").read_text().strip())

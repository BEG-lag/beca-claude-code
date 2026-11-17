#!/usr/bin/env python3
"""Extrae el audio de los clips y mide lo que se puede medir sin oírlo: si hay
sonido, cuánto dura, cuánto ruido de fondo tiene y si el tono cae en el rango de
un maullido. La decisión final se hace escuchando."""
import subprocess, sys, wave
from pathlib import Path
import numpy as np

root = Path(__file__).parent
for clip in sorted((root / "crudo").glob("*.mp4")):
    wav = root / "qa" / f"{clip.stem}.wav"
    r = subprocess.run(["ffmpeg", "-y", "-v", "error", "-i", str(clip), "-vn", "-ac", "1", "-ar", "48000", str(wav)], capture_output=True, text=True)
    if r.returncode or not wav.exists():
        print(f"{clip.stem:22} SIN AUDIO", r.stderr[:80]); continue
    with wave.open(str(wav)) as w:
        x = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float64) / 32768
    win = 480  # 10 ms
    n = len(x) // win
    rms = np.sqrt((x[: n * win].reshape(n, win) ** 2).mean(axis=1)) + 1e-9
    db = 20 * np.log10(rms)
    floor, peak = np.percentile(db, 10), db.max()
    active = db > max(peak - 25, floor + 12)
    idx = np.where(active)[0]
    span = (idx[0] * 0.01, idx[-1] * 0.01) if len(idx) else (0, 0)
    # Tono fundamental por autocorrelación en las ventanas activas.
    f0 = []
    for i in idx[::5]:
        seg = x[i * win : i * win + 2400]
        if len(seg) < 2400: continue
        seg = seg - seg.mean()
        ac = np.correlate(seg, seg, "full")[len(seg) - 1 :]
        lo, hi = 48000 // 1500, 48000 // 150
        lag = lo + int(np.argmax(ac[lo:hi]))
        if ac[lag] > 0.4 * ac[0]: f0.append(48000 / lag)
    med = f"{np.median(f0):.0f} Hz ({np.percentile(f0,10):.0f}-{np.percentile(f0,90):.0f})" if f0 else "sin tono claro"
    print(f"{clip.stem:22} dur={len(x)/48000:.1f}s pico={peak:6.1f}dB fondo={floor:6.1f}dB activo={active.mean()*100:3.0f}% de {span[0]:.2f}s a {span[1]:.2f}s tono={med}")
    subprocess.run(["ffmpeg", "-y", "-v", "error", "-i", str(wav), "-lavfi", "showspectrumpic=s=900x300:legend=0:scale=log:fscale=lin:stop=8000", str(root / "qa" / f"{clip.stem}.png")])

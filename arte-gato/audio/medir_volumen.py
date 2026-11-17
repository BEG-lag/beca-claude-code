#!/usr/bin/env python3
"""Compara qué tan fuerte se percibe cada sonido: nivel máximo con ponderación A
en ventanas de 100 ms. La ponderación A descuenta los graves y por eso refleja
mejor un cascabel agudo frente a un ronroneo grave que el pico de la onda."""
import subprocess, sys
import numpy as np

def lee(ruta):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", ruta, "-ac", "1", "-ar", "48000", "-f", "f32le", "-"], capture_output=True).stdout
    return np.frombuffer(raw, dtype=np.float32).astype(np.float64)

def peso_a(f):
    f = np.maximum(f, 1e-3); a = 12194.0 ** 2
    r = a * f**4 / ((f**2 + 20.6**2) * np.sqrt((f**2 + 107.7**2) * (f**2 + 737.9**2)) * (f**2 + a))
    return r * 10 ** (2.0 / 20)

for ruta in sys.argv[1:]:
    x = lee(ruta)
    n = 4800; mejor = -200.0
    for i in range(0, max(1, len(x) - n), 480):
        s = x[i : i + n]
        s = s * np.hanning(len(s))
        e = np.abs(np.fft.rfft(s)) * peso_a(np.fft.rfftfreq(len(s), 1 / 48000))
        mejor = max(mejor, 10 * np.log10((e**2).sum() / len(s) ** 2 * 2 / 0.375 + 1e-20))
    pico = 20 * np.log10(np.abs(x).max() + 1e-12)
    print(f"{ruta.split('/')[-1]:28} {len(x)/48000:4.2f} s  pico {pico:6.1f} dB  ponderado A {mejor:6.1f} dB")

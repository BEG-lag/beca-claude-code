#!/usr/bin/env python3
"""Mide el hook como lo llama Claude Code: `sh -c` con el JSON por stdin.
Usa otra carpeta de estado para no tocar ~/.axo. Uso: hooks.py <salida.json>"""
import json, os, statistics, subprocess, sys, time

home = os.path.expanduser("~/Library/Caches/AxoBench/estado")
os.makedirs(home, exist_ok=True)
env = dict(os.environ, AXO_HOME=home)
command = "$HOME/.axo/axo-state working"

def run_once(payload):
    start = time.perf_counter()
    subprocess.run(["/bin/sh", "-c", command], input=payload, env=env, stdout=subprocess.DEVNULL)
    return (time.perf_counter() - start) * 1000

def stats(label, payload, count):
    for _ in range(10):
        run_once(payload)
    values = sorted(run_once(payload) for _ in range(count))
    return {
        "caso": label, "n": count,
        "media_ms": round(statistics.fmean(values), 2),
        "p95_ms": round(values[int(count * 0.95)], 2),
        "max_ms": round(values[-1], 2),
    }

def leftovers():
    out = subprocess.run(["ps", "-axo", "stat=,command="], capture_output=True, text=True).stdout
    lines = [l for l in out.splitlines() if "axo-state" in l and "hooks.py" not in l and "grep" not in l]
    zombies = [l for l in out.splitlines() if l.strip().startswith("Z")]
    return len(lines), len(zombies)

small = json.dumps({"hook_event_name": "PreToolUse", "tool_name": "Read", "tool_input": {"file_path": "x" * 200}}).encode()
big = b"x" * (1024 * 1024)
results = [stats("payload 300 B", small, 300), stats("payload 1 MB", big, 40)]

# Vacío: mide solo el arranque del shell, para separar el costo propio.
start_only = []
for _ in range(200):
    t = time.perf_counter()
    subprocess.run(["/bin/sh", "-c", "true"], stdout=subprocess.DEVNULL)
    start_only.append((time.perf_counter() - t) * 1000)
results.append({"caso": "sh vacío (referencia)", "n": 200, "media_ms": round(statistics.fmean(start_only), 2)})

# Ráfaga: 200 hooks a la vez.
before = leftovers()
start = time.perf_counter()
procs = [subprocess.Popen(["/bin/sh", "-c", command], stdin=subprocess.PIPE, env=env, stdout=subprocess.DEVNULL) for _ in range(200)]
for p in procs:
    p.stdin.write(small); p.stdin.close()
codes = [p.wait() for p in procs]
elapsed = (time.perf_counter() - start) * 1000
time.sleep(0.5)
after = leftovers()
state = open(os.path.join(home, "state")).read().strip()
temporals = [n for n in os.listdir(home) if n.startswith(".state")]
results.append({
    "caso": "200 en paralelo", "total_ms": round(elapsed, 1), "codigos_no_cero": sum(c != 0 for c in codes),
    "restantes_antes_despues": [before[0], after[0]], "zombis_antes_despues": [before[1], after[1]],
    "estado_final": state, "temporales_huerfanos": len(temporals),
})
json.dump(results, open(sys.argv[1], "w"), indent=1, ensure_ascii=False)
for r in results:
    print(r)

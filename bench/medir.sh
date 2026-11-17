#!/bin/bash
# Mide a BeCa en una instancia aislada: usa otra carpeta de estado, así que los
# hooks reales de Claude Code no la tocan y las pruebas no tocan ~/.axo.
# Uso: bench/medir.sh <etiqueta>
cd "$(dirname "$0")/.." || exit 1
ETIQUETA="${1:?falta etiqueta}"
OUT="bench/resultados/$ETIQUETA"
BIN="$HOME/Applications/BeCa.app/Contents/MacOS/BeCa"
CACHE="$HOME/Library/Caches/AxoBench"
export AXO_HOME="$CACHE/estado"
mkdir -p "$OUT" "$AXO_HOME/status"
rm -f "$AXO_HOME/state" "$AXO_HOME/disabled" "$AXO_HOME/hidden"
clang -O2 -o "$CACHE/muestrear" bench/muestrear.c || exit 1

ws_cpu() { ps -o time= -p "$(pgrep -x WindowServer | head -1)" | tr -d ' '; }
estado() { printf '%s\n' "$1" >"$AXO_HOME/.s" && mv -f "$AXO_HOME/.s" "$AXO_HOME/state"; }
lanzar() { nohup "$BIN" >/dev/null 2>&1 & PID=$!; sleep "${1:-10}"; }
cerrar() { kill "$PID" 2>/dev/null; wait "$PID" 2>/dev/null; sleep 1; }
escenario() {
  local nombre="$1"
  echo "$nombre ws_inicio $(ws_cpu)" >>"$OUT/windowserver.txt"
  "$CACHE/muestrear" "$PID" 60 "$OUT/$nombre.csv"
  echo "$nombre ws_fin $(ws_cpu)" >>"$OUT/windowserver.txt"
  vmmap -summary "$PID" 2>/dev/null >"$OUT/$nombre-vmmap.txt"
}

: >"$OUT/windowserver.txt"
~/.axo/axo cerrar >/dev/null 2>&1; sleep 1

lanzar 10
escenario quieta
# Sin eventos desde hace más de un minuto.
escenario reposo
estado working; sleep 2
escenario animada

# Cambios de estado seguidos: si algo se acumula, aquí crece la memoria.
( for i in $(seq 1 600); do for s in working reviewing attention completed; do estado "$s"; sleep 0.025; done; done ) &
RAFAGA=$!
escenario rafaga
kill "$RAFAGA" 2>/dev/null; wait "$RAFAGA" 2>/dev/null
cerrar

# Oculta con la animación activa de fondo.
estado working
lanzar 5
: >"$AXO_HOME/hidden"
sleep 2
escenario oculta
rm -f "$AXO_HOME/hidden"
cerrar

echo "cerrada ws_inicio $(ws_cpu)" >>"$OUT/windowserver.txt"
sleep 60
echo "cerrada ws_fin $(ws_cpu)" >>"$OUT/windowserver.txt"
echo "procesos BeCa al cerrar: $(pgrep -x BeCa | wc -l | tr -d ' ')" >"$OUT/cerrada.txt"

~/.axo/axo abrir
echo "listo $ETIQUETA"

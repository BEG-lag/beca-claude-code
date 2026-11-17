#!/bin/bash
# Costo de componer la ventana: alterna cerrada y animando para repartir el ruido.
# Uso: bench/windowserver.sh <etiqueta>
cd "$(dirname "$0")/.." || exit 1
OUT="bench/resultados/$1"; mkdir -p "$OUT"; F="$OUT/windowserver-ab.csv"
BIN="$HOME/Applications/BeCa.app/Contents/MacOS/BeCa"
export AXO_HOME="$HOME/Library/Caches/AxoBench/estado"
mkdir -p "$AXO_HOME/status"; rm -f "$AXO_HOME/hidden" "$AXO_HOME/disabled"
WS=$(pgrep -x WindowServer | head -1)
seg() { ps -o time= -p "$WS" | tr -d ' ' | awk -F: '{print $1*60+$2}'; }
medir() { local a b; a=$(seg); sleep 15; b=$(seg); echo "$1,$(awk -v a="$a" -v b="$b" 'BEGIN{printf "%.2f",100*(b-a)/15}')" >>"$F"; }
~/.axo/axo cerrar >/dev/null 2>&1; sleep 1
echo "caso,ws_cpu" >"$F"
for i in 1 2 3 4 5 6; do
  medir cerrada
  printf 'working\n' >"$AXO_HOME/state"
  nohup "$BIN" >/dev/null 2>&1 & P=$!
  sleep 3
  medir animada
  kill "$P"; wait "$P" 2>/dev/null; sleep 1
done
~/.axo/axo abrir
python3 - "$F" <<'P'
import csv,statistics,sys
r=list(csv.DictReader(open(sys.argv[1])))
c=[float(x['ws_cpu']) for x in r if x['caso']=='cerrada']; a=[float(x['ws_cpu']) for x in r if x['caso']=='animada']
d=[y-x for x,y in zip(c,a)]
print('cerrada',c); print('animada',a)
print(f'media cerrada {statistics.fmean(c):.2f}  media animada {statistics.fmean(a):.2f}  delta {statistics.fmean(d):.2f} +- {statistics.stdev(d):.2f} puntos')
P

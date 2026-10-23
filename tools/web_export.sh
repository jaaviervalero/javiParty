#!/usr/bin/env bash
# Exporta la versión web (HTML5, WebGL1/GLES2) a build/web/.
#   tools/web_export.sh            exportar (build/web/index.html)
#   tools/web_export.sh --serve    exportar y servir build/ en http://127.0.0.1:8000
# La carpeta servida es build/, así que el juego queda en /web/ y el mando en /web/m/.
set -euo pipefail
cd "$(dirname "$0")/.."

PRESET="Web"
OUT="build/web"

echo "== Exportando $OUT/index.html"
mkdir -p "$OUT"
touch build/.gdignore  # que Godot no importe lo exportado como recursos
# Borrar los ficheros principales para no confundir un fallo con una exportación vieja.
rm -f "$OUT/index.html" "$OUT/index.js" "$OUT/index.wasm" "$OUT/index.pck"
# Importar recursos si hace falta (la primera vez tarda; es lo mismo que abre el editor).
godot3 --headless --path . --editor --quit >/dev/null 2>&1 || true
out=$(godot3 --headless --path . --export "$PRESET" "$OUT/index.html" 2>&1) || true
if [ ! -f "$OUT/index.html" ] || echo "$out" | grep -qE "^ERROR|failed"; then
	echo "$out" | grep -vE "^$|^Godot" | tail -20
	[ -f "$OUT/index.html" ] || { echo "!! La exportación falló"; exit 1; }
fi
for f in index.html index.js index.wasm index.pck; do
	[ -f "$OUT/$f" ] || { echo "!! Falta $OUT/$f"; echo "$out" | tail -20; exit 1; }
done

# Red del host y Trystero (los escribe otro agente; pueden no existir todavía).
for f in web/host/net.js web/vendor/trystero.js; do
	if [ -f "$f" ]; then
		cp "$f" "$OUT/"
	fi
done

# Mandos: build/m/index.html (+ style.css, controller.js y trystero.js).
mkdir -p "$OUT/m"
cp -R web/controller/. "$OUT/m/"
if [ -f web/vendor/trystero.js ]; then
	cp web/vendor/trystero.js "$OUT/m/"
fi

# Tamaños: total en disco y comprimido de lo que más pesa (.wasm y .pck).
human() {
	awk -v b="$1" 'BEGIN {
		split("B KB MB GB", u, " ");
		i = 1;
		while (b >= 1024 && i < 4) { b /= 1024; i++ }
		printf (i == 1 ? "%.0f %s" : "%.1f %s"), b, u[i]
	}'
}
gzip_size() { gzip -9 -c "$1" | wc -c | tr -d ' '; }

total_bytes=$(du -sb "$OUT" | cut -f1)
echo "== Tamaños"
printf "   %-18s %10s\n" "en disco" "$(human "$total_bytes")"
gz_total=0
for f in "$OUT/index.wasm" "$OUT/index.pck"; do
	raw=$(stat -c%s "$f")
	gz=$(gzip_size "$f")
	gz_total=$((gz_total + gz))
	printf "   %-18s %10s  ->  %10s gzip\n" "$(basename "$f")" "$(human "$raw")" "$(human "$gz")"
done
printf "   %-18s %10s\n" "wasm+pck gzip" "$(human "$gz_total")"
if [ "$gz_total" -gt $((25 * 1024 * 1024)) ]; then
	echo "   !! Por encima del objetivo de 25 MB comprimido"
fi
echo "   en: $(pwd)/$OUT"

if [ "${1:-}" = "--serve" ]; then
	echo "== http://127.0.0.1:8000/web/  (Ctrl+C para parar)"
	cd build
	exec python3 -m http.server 8000
fi

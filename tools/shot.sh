#!/usr/bin/env bash
# Captura sin ventana (pantalla virtual Xvfb) para revisar el aspecto visual.
#   tools/shot.sh <id_minijuego> [jugadores] [salida.png]   -> captura a mitad de partida
#   tools/shot.sh select [salida.png]                       -> selector de juego libre
# Requiere xorg-server-xvfb.
set -eu
cd "$(dirname "$0")/.."
run() { timeout 120 xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --display-driver x11 \
	--rendering-driver opengl3 "$@" 2>&1 | grep -E "SCRIPT ERROR|Parse Error|^ERROR" || true; }
if [ "${1:?uso: tools/shot.sh <id>|select}" = select ]; then
	out="${2:-/tmp/javiparty_select.png}"
	run tests/screenshot.tscn -- res://ui/minigame_select.tscn "$out"
else
	out="${3:-/tmp/javiparty_$1.png}"
	run tests/minigame_smoke.tscn -- "$1" "${2:-4}" "$out"
fi
echo "$out"

#!/usr/bin/env bash
# Prueba automática de un minijuego con bots (4 por defecto) y también con 1 jugador.
#   tools/smoke.sh <id>
# Falla si hay errores de script/parseo o si la partida no termina bien.
set -u
cd "$(dirname "$0")/.."
id="${1:?uso: tools/smoke.sh <id_del_minijuego>}"
# Ojo: --editor --quit aborta el escaneo de recursos a medias (y con él la caché de
# class_name), así que solo se importa si aún no hay caché.
[ -f .import/global_script_class_cache.cfg ] || godot3 --headless --path . --editor --quit >/dev/null 2>&1
status=0
for n in 4 1; do
	out=$(timeout 120 godot3 --headless --path . tests/minigame_smoke.tscn -- "$id" "$n" 2>&1)
	echo "$out" | grep -E "SMOKE|SCRIPT ERROR|ERROR|Parse Error|WARNING" | grep -v "^WARNING: .*ObjectDB" | head -40
	if echo "$out" | grep -qE "SCRIPT ERROR|Parse Error|^ERROR|  ERROR"; then
		echo ">> $id con $n jugador(es): HAY ERRORES"; status=1
	elif ! echo "$out" | grep -q "SMOKE OK"; then
		echo ">> $id con $n jugador(es): NO TERMINÓ BIEN"; status=1
	else
		echo ">> $id con $n jugador(es): OK"
	fi
done
exit $status

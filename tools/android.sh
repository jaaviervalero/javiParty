#!/usr/bin/env bash
# Exporta el APK de depuración y lo instala y abre en la tele por ADB WiFi.
#   tools/android.sh <ip_tele[:puerto]>   exportar + instalar + abrir
#   tools/android.sh --export             solo exportar (build/javiparty.apk)
#   tools/android.sh <ip> --log           además, ver el log de Godot de la tele
# En la tele: Ajustes > Opciones de desarrollador > Depuración USB/ADB por red activada.
set -euo pipefail
cd "$(dirname "$0")/.."

SDK="${ANDROID_HOME:-$HOME/.local/share/android-sdk}"
ADB="$SDK/platform-tools/adb"
APK="build/javiparty.apk"
PKG="com.javiparty.app"

echo "== Exportando $APK"
mkdir -p build
godot --headless --path . --import >/dev/null 2>&1
out=$(godot --headless --path . --export-debug "Android TV" "$APK" 2>&1) || true
if [ ! -f "$APK" ] || echo "$out" | grep -qE "ERROR|failed"; then
	echo "$out" | grep -vE "^$|^Godot" | tail -20
	[ -f "$APK" ] || { echo "!! La exportación falló"; exit 1; }
fi
ls -lh "$APK" | awk '{print "   " $5 " " $9}'
[ "${1:-}" = "--export" ] && exit 0

TV="${1:?uso: tools/android.sh <ip_tele[:puerto]> | --export}"
[[ "$TV" == *:* ]] || TV="$TV:5555"
echo "== Conectando a $TV (acepta el aviso de depuración en la tele la primera vez)"
"$ADB" connect "$TV"
"$ADB" -s "$TV" wait-for-device
echo "   $("$ADB" -s "$TV" shell getprop ro.product.model | tr -d '\r') · Android $("$ADB" -s "$TV" shell getprop ro.build.version.release | tr -d '\r') · $("$ADB" -s "$TV" shell getprop ro.product.cpu.abi | tr -d '\r')"
echo "== Instalando"
"$ADB" -s "$TV" install -r "$APK"
echo "== Abriendo"
"$ADB" -s "$TV" shell am force-stop "$PKG" || true
"$ADB" -s "$TV" shell monkey -p "$PKG" -c android.intent.category.LEANBACK_LAUNCHER 1 >/dev/null 2>&1 \
	|| "$ADB" -s "$TV" shell monkey -p "$PKG" 1 >/dev/null
if [ "${2:-}" = "--log" ]; then
	"$ADB" -s "$TV" logcat -c
	"$ADB" -s "$TV" logcat -s godot:V
fi

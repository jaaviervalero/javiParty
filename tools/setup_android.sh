#!/usr/bin/env bash
# Prepara este PC para exportar javiParty a Android (sin sudo, todo en ~/.local/share):
#   1. Plantillas de exportación de Godot (de la versión instalada).
#   2. Android SDK mínimo: cmdline-tools, platform-tools (adb), build-tools y plataforma.
#   3. Keystore de depuración para firmar el APK.
#   4. Rutas del SDK y del JDK en la configuración del editor de Godot.
# Se puede volver a ejecutar: salta lo que ya esté hecho.
set -euo pipefail

SDK="${ANDROID_HOME:-$HOME/.local/share/android-sdk}"
CMDLINE_ZIP="commandlinetools-linux-11076708_latest.zip"
BUILD_TOOLS="35.0.0"
PLATFORM="android-35"
JAVA_HOME="${JAVA_HOME:-$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")}"

# Versión de Godot: "4.7.2.stable.arch_linux.xxx" -> carpeta 4.7.2.stable, release 4.7.2-stable
GV="$(godot3 --version | cut -d. -f1-4)"
NUM="${GV%.*}"; KIND="${GV##*.}"
TPL_DIR="$HOME/.local/share/godot/export_templates/$GV"
# Temporal en disco (no en /tmp, que suele ser RAM y las plantillas ocupan ~3 GB al descomprimir).
mkdir -p "$HOME/.cache"
TMP="$(mktemp -d -p "$HOME/.cache" javiparty-setup.XXXX)"
trap 'rm -rf "$TMP"' EXIT

echo "== Godot $GV · JDK en $JAVA_HOME · SDK en $SDK"
"$JAVA_HOME/bin/java" -version 2>&1 | head -1

# --- 1. Plantillas ---
if [ -f "$TPL_DIR/android_debug.apk" ]; then
	echo "== Plantillas ya instaladas"
else
	URL="https://github.com/godotengine/godot/releases/download/$NUM-$KIND/Godot_v$NUM-${KIND}_export_templates.tpz"
	echo "== Descargando plantillas: $URL"
	curl -L --fail -o "$TMP/templates.tpz" "$URL"
	mkdir -p "$TPL_DIR"
	# Solo lo de Android (el paquete trae todas las plataformas).
	unzip -q "$TMP/templates.tpz" 'templates/android_*' 'templates/version.txt' -d "$TMP/tpl"
	cp -r "$TMP/tpl/templates/." "$TPL_DIR/"
	rm -f "$TMP/templates.tpz"
	echo "   -> $TPL_DIR"
fi

# --- 2. Android SDK ---
SDKM="$SDK/cmdline-tools/latest/bin/sdkmanager"
if [ ! -x "$SDKM" ]; then
	echo "== Descargando Android cmdline-tools"
	curl -L --fail -o "$TMP/cmdline.zip" "https://dl.google.com/android/repository/$CMDLINE_ZIP"
	mkdir -p "$SDK/cmdline-tools"
	unzip -q "$TMP/cmdline.zip" -d "$TMP/cl"
	rm -rf "$SDK/cmdline-tools/latest"
	mv "$TMP/cl/cmdline-tools" "$SDK/cmdline-tools/latest"
fi
export JAVA_HOME
echo "== Instalando platform-tools, build-tools;$BUILD_TOOLS, platforms;$PLATFORM (acepta licencias)"
yes | "$SDKM" --sdk_root="$SDK" --licenses >/dev/null || true
"$SDKM" --sdk_root="$SDK" "platform-tools" "build-tools;$BUILD_TOOLS" "platforms;$PLATFORM"

# --- 3. Keystore de depuración (el mismo que generaría el editor) ---
KS_DIR="$HOME/.local/share/godot/keystores"
KS="$KS_DIR/debug.keystore"
if [ ! -f "$KS" ]; then
	echo "== Creando keystore de depuración"
	mkdir -p "$KS_DIR"
	"$JAVA_HOME/bin/keytool" -genkeypair -v -keystore "$KS" -storepass android -alias androiddebugkey \
		-keypass android -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Android Debug,O=Android,C=US" >/dev/null
fi

# --- 4. Configuración del editor de Godot ---
MINOR="$(echo "$GV" | cut -d. -f1)"  # Godot 3 usa editor_settings-3.tres
ES="$HOME/.config/godot/editor_settings-$MINOR.tres"
if [ ! -f "$ES" ]; then
	echo "== Generando configuración del editor"
	timeout 60 godot3 --headless --editor --quit --path "$(dirname "$0")/.." >/dev/null 2>&1 || true
fi
if [ -f "$ES" ]; then
	set_setting() {
		local key="$1" value="$2"
		if grep -q "^$key = " "$ES"; then
			sed -i "s|^$key = .*|$key = \"$value\"|" "$ES"
		else
			sed -i "/^\[resource\]/a $key = \"$value\"" "$ES"
		fi
	}
	set_setting "export/android/android_sdk_path" "$SDK"
	set_setting "export/android/java_sdk_path" "$JAVA_HOME"
	set_setting "export/android/debug_keystore" "$KS"
	set_setting "export/android/debug_keystore_user" "androiddebugkey"
	set_setting "export/android/debug_keystore_pass" "android"
	echo "== Rutas guardadas en $ES"
else
	echo "!! No encontré $ES: abre una vez el editor de Godot y vuelve a ejecutar este script"
fi

echo
echo "Listo. adb está en $SDK/platform-tools/adb"
echo "Siguiente: tools/android.sh <IP_de_la_tele>"

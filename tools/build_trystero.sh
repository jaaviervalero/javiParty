#!/usr/bin/env bash
# Genera web/vendor/trystero.js: Trystero (Nostr + torrent) en un único ESM
# minificado, sin CDN ni dependencias externas. Versión fijada a propósito.
#   tools/build_trystero.sh
# Deja también web/vendor/TRYSTERO_LICENSE (MIT de Trystero y lo que incluye).
# La carpeta temporal se puede cambiar con TRYSTERO_BUILD_DIR.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

TRYSTERO_VERSION="0.26.0"   # última estable al escribir esto (npm dist-tag latest)
ESBUILD_VERSION="0.28.2"
BUILD_DIR="${TRYSTERO_BUILD_DIR:-${TMPDIR:-/tmp}/javiparty-trystero-build}"
OUT="web/vendor/trystero.js"

echo "== Instalando Trystero $TRYSTERO_VERSION y esbuild $ESBUILD_VERSION en $BUILD_DIR"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"
npm init -y >/dev/null 2>&1
npm install --no-audit --no-fund --no-save \
	trystero@"$TRYSTERO_VERSION" \
	@"trystero-p2p/nostr@$TRYSTERO_VERSION" \
	@"trystero-p2p/torrent@$TRYSTERO_VERSION" \
	esbuild@"$ESBUILD_VERSION" >/dev/null

# Solo estas dos estrategias: MQTT mete mqtt.js y multiplica el tamaño (>400 KB).
cat > entry.mjs <<'EOF'
export { joinRoom as joinNostr } from "trystero/nostr";
export { joinRoom as joinTorrent } from "@trystero-p2p/torrent";
EOF

echo "== Empaquetando $OUT"
./node_modules/.bin/esbuild entry.mjs \
	--bundle --format=esm --minify --platform=browser --target=es2020 \
	--legal-comments=eof \
	--outfile="$ROOT/$OUT" --log-level=warning

# Licencias de todo lo que acaba dentro del bundle.
cd "$ROOT"
mkdir -p web/vendor
{
	echo "Trystero $TRYSTERO_VERSION - MIT"
	echo "https://github.com/dmotz/trystero"
	echo
	for pkg in trystero @trystero-p2p/nostr @trystero-p2p/torrent @trystero-p2p/core @noble/secp256k1; do
		lic="$BUILD_DIR/node_modules/$pkg/LICENSE"
		[ -f "$lic" ] || continue
		echo "----------------------------------------------------------------------"
		echo "$pkg"
		echo "----------------------------------------------------------------------"
		cat "$lic"
		echo
	done
} > web/vendor/TRYSTERO_LICENSE

ls -lh "$OUT" web/vendor/TRYSTERO_LICENSE | awk '{print "   " $5 " " $9}'

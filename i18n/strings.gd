class_name Strings
extends Reference
## Textos de la interfaz en español e inglés. Se registran como Translation al
## arrancar (Settings), así que basta con poner la clave como texto de un Control
## o usar tr("CLAVE").

const LOCALES := ["es", "en"]

const TEXT := {
	"TAGLINE": ["Minijuegos con tu móvil como mando", "Minigames with your phone as a controller"],
	"PLAYER_N": ["Jugador %d", "Player %d"],
	"WAITING_PLAYER": ["Esperando mando…", "Waiting for controller…"],
	"STATUS_CONNECTED": ["Conectado", "Connected"],
	"STATUS_DISCONNECTED": ["Desconectado", "Disconnected"],
	"BTN_PLAY": ["Jugar", "Play"],
	"BTN_SCAN_ON": ["Búsqueda: activada", "Search: on"],
	"BTN_SCAN_OFF": ["Búsqueda: desactivada", "Search: off"],
	"BTN_QR": ["QR del mando", "Controller QR"],
	"BTN_CLOSE": ["Cerrar", "Close"],
	"QR_TITLE": ["El mando de javiParty", "The javiParty controller"],
	"QR_STEPS": [
		"1. Instala DSU Controller (v3.0.6 o superior).\n2. En la app, escanea este código para añadir el mando.\n3. Elige el mando de javiParty, ponte en la misma wifi que la tele y deja la app abierta.",
		"1. Install DSU Controller (v3.0.6 or later).\n2. In the app, scan this code to add the controller.\n3. Pick the javiParty controller, join the TV's Wi-Fi and keep the app open."],
	"BTN_MANUAL_IP": ["Añadir IP a mano", "Add IP manually"],
	"BTN_LANGUAGE": ["Idioma: Español", "Language: English"],
	"BTN_DEBUG": ["Depuración", "Debug info"],
	"BTN_CONNECT": ["Conectar", "Connect"],
	"BTN_CANCEL": ["Cancelar", "Cancel"],
	"BTN_QUIT": ["Salir", "Quit"],
	"MANUAL_IP_TITLE": ["IP del móvil", "Phone IP"],
	"MANUAL_IP_HINT": ["Mírala en la app DSU del móvil (puerto 26760).", "Check it in the phone's DSU app (port 26760)."],
	"INVALID_IP": ["IP no válida", "Invalid IP"],
	"SCANNING": ["Buscando mandos en %s", "Looking for controllers on %s"],
	"SCAN_IDLE": ["Búsqueda automática desactivada", "Automatic search is off"],
	"NO_NETWORK": ["Sin red local: conecta la tele a la wifi", "No local network: connect the TV to Wi-Fi"],
	"HOW_TO_CONNECT": [
		"Abre la app DSU Controller en tu móvil, en la misma wifi que la tele.",
		"Open the DSU Controller app on your phone, on the same Wi-Fi as the TV."],
	"NOTHING_FOUND": [
		"No encuentro ningún mando. Comprueba: que el móvil está en la misma wifi (no la de invitados), que el router no aísla a los clientes, y que la app está abierta en primer plano y sin ahorro de energía.",
		"No controllers found. Check that the phone is on the same Wi-Fi (not a guest network), that the router doesn't isolate clients, and that the app is open in the foreground with power saving off."],
	"BATTERY": ["Batería", "Battery"],
	"BAT_0": ["?", "?"],
	"BAT_1": ["casi vacía", "almost empty"],
	"BAT_2": ["baja", "low"],
	"BAT_3": ["media", "medium"],
	"BAT_4": ["alta", "high"],
	"BAT_5": ["llena", "full"],
	"BAT_CHARGING": ["cargando", "charging"],
	"BAT_CHARGED": ["cargada", "charged"],
}


static func build_translations() -> Array:
	var out: Array = []
	for i in LOCALES.size():
		var t := Translation.new()
		t.locale = LOCALES[i]
		for key in TEXT:
			t.add_message(key, TEXT[key][i])
		out.append(t)
	return out

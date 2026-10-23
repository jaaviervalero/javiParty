# Plan: mando web y versión web de javiParty

Estado: **fases 1-3 hechas en la rama `web`** (falta publicar en Pages y probar con móviles reales). Rama `web` (worktree
`~/Projects/javiParty-web`). Lo que ya funciona está congelado en el tag
`tv-android-v1` (APK de la tele, mandos DSU) y `pc-godot47` (PC, Godot 4.7).

## Objetivo

Quitar fricción. Hoy cada amigo tiene que instalar DSU Controller, configurarla y
estar en el mismo Wi-Fi. Queremos:

- **En la tele**: se sigue jugando con el APK de Android TV.
- **Con un portátil, en cualquier sitio**: se abre un enlace y la pantalla del
  portátil ES el juego (nada de instalables ni de conectarlo a otra pantalla).
- **Los mandos, en los dos casos**: escanear un QR con la cámara del móvil →
  página web → "Eres el **Jugador 2**". Nada que instalar, ninguna cuenta.
- **Conexión directa** móvil ↔ host: el tráfico de juego no pasa por servidores.

## Decisiones tomadas

| Tema | Decisión |
|---|---|
| Motor | Godot 3.6 en todo (APK y export HTML5 comparten código). |
| Mando | Una sola página web (`web/controller/`), igual para tele y portátil. |
| Tele | El APK hace de servidor: sirve la página y recibe los mandos por WebSocket en la LAN. Sin internet. |
| Portátil | Godot exportado a HTML5. Mandos por **WebRTC directo**; solo el apretón de manos va por redes públicas (Trystero: Nostr/MQTT/BitTorrent), sin servidor propio. |
| Páginas web | Estáticas en **GitHub Pages** de este repo (gratis, no se duerme). |
| DSU | Se queda en el APK como alternativa; en la web no existe (sin UDP ni hilos). |
| Mando contextual | Cada minijuego ya declara `controls`; el host se los manda al móvil y este enseña solo esos botones, con su texto ("Embestir", "Moverse"). |
| Sensores | No hacen falta: ningún minijuego usa acelerómetro ni giroscopio (revisados los 18). |
| Teclado del portátil | NO es jugador: solo se juega con móviles. |
| Más adelante | Si gusta: VPS + dominio, y servidor de apretón de manos propio (opción B). |

## Cómo se conecta un mando

### Tele (APK)

```
 Móvil ──(cámara lee QR)──▶ http://192.168.1.17:8080      página del mando (la sirve el APK)
 Móvil ◀══ WebSocket ══▶ ws://192.168.1.17:8081            entradas y avisos, directo por Wi-Fi
```

- El QR lleva la IP de la tele en la LAN (`IP.get_local_addresses()` +
  `LAN.private_ipv4_prefixes`).
- El móvil TIENE que estar en el mismo Wi-Fi. Para que no sea un lío, la tele
  puede enseñar un **segundo QR de Wi-Fi** (`WIFI:T:WPA;S:<red>;P:<clave>;;`):
  la red y la clave se meten una vez en la tele y se guardan en `user://`.
  (Ojo: la clave queda en claro en el almacenamiento de la app; es la de casa y
  solo se enseña si el dueño lo activa.)
- Dos puertos porque `WebSocketServer` de 3.6 no sirve HTTP normal: 8080 lo
  sirve un `TCP_Server` mínimo (GET de 3-4 ficheros estáticos), 8081 es el
  `WebSocketServer`. Si un puerto está ocupado, se prueba el siguiente y el QR
  lleva el que toque.
- Al ser `http` (no `https`), en el móvil no hay Wake Lock API: para que la
  pantalla no se bloquee se usa el truco del vídeo en bucle invisible (NoSleep).
  Vibración y pantalla completa sí funcionan en `http`.

### Portátil (web)

```
 Portátil abre  https://jaaviervalero.github.io/javiParty/            el juego (HTML5)
 Móvil   abre   https://jaaviervalero.github.io/javiParty/m#KQZT      el mando, sala KQZT
 Apretón de manos por redes públicas (unos segundos) ─▶ WebRTC DataChannel directo
```

- La sala es un código de 4 letras sin ambigüedades (sin O/0, I/1).
- Mismo Wi-Fi: directo, ~5 ms. Móvil con 4G: suele funcionar con STUN público;
  detrás de algunas operadoras (NAT simétrico) no hay forma sin TURN (= relevo,
  descartado): el mando lo dice claro en vez de quedarse colgado.
- La red y el WebRTC viven en JavaScript, en la página del host
  (`web/host/net.js`); Godot los lee con el singleton `JavaScript`
  (`get_interface` + `create_callback`). Así no dependemos del WebRTC de
  Godot 3.6 (que en HTML5 existe, pero la parte de señalización la tendríamos
  que escribir igual).

## Protocolo (igual en WebSocket y en WebRTC)

JSON pequeño, un mensaje por evento.

Móvil → host:

| Mensaje | Cuándo |
|---|---|
| `{"t":"hello","id":"<uuid>","v":1}` | al conectar; `id` guardado en `localStorage` del móvil |
| `{"t":"in","b":<bits>,"x":<-1..1>,"y":<-1..1>,"n":<seq>}` | al cambiar algo y cada 250 ms (latido) |
| `{"t":"pong","n":<seq>}` | respuesta a ping (para medir latencia) |

`b` son ya los botones LÓGICOS de `Pad` (UP=1 … HOME=1024): el móvil no tiene
"diseños" raros que traducir. En el juego, `Pad.LAYOUT_WEB` es la identidad.

Host → móvil:

| Mensaje | Para qué |
|---|---|
| `{"t":"welcome","player":2,"color":"#ec5a5a"}` | eres el jugador N, en este color |
| `{"t":"full"}` | ya hay 4: "sala llena" |
| `{"t":"layout","controls":[["A","Embestir"],["stick","Moverse"]]}` | mando del minijuego actual (menús: cruceta + A/B) |
| `{"t":"vibrate","ms":80}` | golpe, gol, eliminación… (solo Android; iOS lo ignora) |
| `{"t":"ping","n":<seq>}` | cada segundo; si en 3 s no hay nada, desconectado |

Identidad: el `id` del móvil sustituye a la MAC. Recargar la página o bloquear el
móvil → vuelve a su jugador. (Arregla de raíz lo de "el mando del amigo me echó".)

## Cambios en el juego

Todo detrás de una interfaz común, para que `PlayerManager` y los 18 minijuegos
no cambien:

| Fichero | Qué |
|---|---|
| `net/web_pad.gd` (nuevo) | Mando web: mismos campos que `DSUController` (`buttons`, `left_stick`, `connected`, `device_id()`, `ip`, `battery`, `key`). |
| `net/web_hub.gd` (nuevo, autoload `WebHub`) | Recibe mandos web y emite `controller_connected/disconnected` como `DSUClient`. Dos transportes: |
| `net/web_lan_server.gd` (nuevo) | Transporte del APK/escritorio: `TCP_Server` (páginas) + `WebSocketServer`. |
| `net/web_rtc_bridge.gd` (nuevo) | Transporte HTML5: puente con `web/host/net.js` vía `JavaScript`. |
| `core/player_manager.gd` | Escucha también a `WebHub`; `layout` del jugador según el tipo de mando. |
| `core/minigame_base.gd` | Al empezar cada juego, `WebHub.send_layout(controls)`; en menús, el de navegación. |
| `ui/main_menu.gd` | Pantalla "Escanea para jugar": QR grande + enlace corto + código. En el APK, botón "QR del Wi-Fi" y lo de DSU en un submenú. |
| `ui/qr.gd` (nuevo) | Generador de QR en GDScript (hoy el QR es un PNG fijo; ahora la URL cambia con la IP/sala). |
| `project.godot` | `DSUClient`/`NetworkScanner` no arrancan en HTML5 (`OS.has_feature("HTML5")`). |
| `ui/debug_overlay.gd` | Muestra también los mandos web (latencia, mensajes/s). |

Página del mando (`web/controller/`, sin framework, una sola versión):

- `index.html` + `controller.js` + `style.css`, cargan en <100 KB.
- Vertical. Cruceta, A, B, 1, 2, −, +, y zona de stick (arrastrar) si el juego
  lo pide. Con `layout` enseña solo los botones del juego, con su texto.
- Multitáctil (dos dedos: cruceta + A a la vez), sin zoom ni selección de texto,
  sin retraso de 300 ms (`touch-action: none`).
- Botón grande con el color y número del jugador; "Pantalla completa" al tocar.
- Mismo código para los dos transportes: detecta si viene de `http://<ip>` (tele,
  WebSocket) o de GitHub Pages con `#SALA` (WebRTC).

## Fases

Cada fase acaba con algo que se puede probar y con su commit. Lo de la tele se
une a `main` al terminar la fase 1 y sale como `tv-android-v2`.

### Fase 1 — Mando web en la tele (APK)

Lo más rápido para saber si el mando web se siente bien: sin internet ni
apretón de manos.

1. `web/controller/` con la cruceta + A/B/1/2/−/+ (sin contextual aún).
2. `web_lan_server.gd`, `web_pad.gd`, `WebHub`; `PlayerManager` los escucha.
3. Generador de QR y pantalla "Escanea para jugar" con la URL de la tele.
4. Empaquetar `web/controller/` dentro del APK (`include_filter` del preset).

Criterios: escaneo → jugador en <5 s; dos móviles a la vez sin pisarse;
recargar la página recupera el jugador; jugar 2-3 minijuegos sin cortes; DSU
sigue funcionando a la vez.
Pruebas: `tests/web_protocol.gd` (mensajes, identidad, reconexión, sala llena)
y un móvil simulado en Python (`tools/web_pad_sim.py`) para probar sin móvil.

### Fase 2 — El juego en el navegador del portátil

1. Bajar las plantillas HTML5 de 3.6.3 (`webassembly_release.zip`, sin hilos).
2. Preset "Web", shell HTML propio con pantalla "Pulsa para empezar" (los
   navegadores no dejan sonar nada hasta que el usuario toca) y pantalla
   completa.
3. Desactivar DSU/escáner en HTML5.
4. Comprobar fuentes, rendimiento (60 fps en un portátil normal) y tamaño de
   descarga (objetivo <25 MB comprimido).

Criterios: el juego arranca y va fluido en Chrome y Firefox (se juega con los móviles, fase 3).

### Fase 3 — Mandos por WebRTC y publicación

1. `web/host/net.js` con Trystero (versión fijada, servida desde el propio
   repo, sin CDN) y varias estrategias de apretón a la vez por si una cae.
   Hecho: Trystero 0.26.0, Nostr + torrent (MQTT descartado: 410 KB),
   `web/vendor/trystero.js` (77 KB) generado con `tools/build_trystero.sh`.
2. `web_rtc_bridge.gd`; sala de 4 letras; QR con `…/m/#SALA`. El juego va en
   `…/javiParty/jugar/` y el mando en `…/javiParty/m/` (`tools/web_export.sh`
   deja esa estructura en `build/web/`).
3. GitHub Actions: exportar con `godot3` y publicar en GitHub Pages en cada
   push a `web` (o a mano con `tools/web_publish.sh` si Actions da guerra).

Criterios: con el portátil y dos móviles en el mismo Wi-Fi, como en la fase 1;
un móvil en 4G se conecta o recibe un mensaje claro; medir latencia real.

### Fase 4 — Pulido

- Mando contextual con `controls` de cada minijuego.
- Vibración en golpes/eliminaciones; latencia en el overlay de depuración.
- QR del Wi-Fi en la tele.
- Avisos claros: sala llena, el host se ha cerrado, sin conexión.
- Probar en iPhone (Safari) y Android (Chrome) reales, con amigos.

## Riesgos y cómo los vigilamos

| Riesgo | Plan |
|---|---|
| Redes públicas de apretón caídas o lentas | Varias estrategias a la vez; si molesta, servidor propio mínimo (Cloudflare Worker o el VPS). |
| 4G detrás de NAT simétrico | Sin TURN no hay solución directa: mensaje claro. Es raro jugando en casa. |
| `WebSocketServer` de 3.6 en Android | Probarlo lo primero en la fase 1 (prueba de 30 líneas antes de construir encima). |
| Rendimiento del HTML5 de 3.6 | Es WebGL 1 (lo mismo que GLES2, que ya va). Medir en la fase 2. |
| Pantalla del móvil que se bloquea | NoSleep (vídeo en bucle) en `http`; Wake Lock API en `https`. |
| Safari de iPhone y el multitáctil | Probar pronto con un iPhone real. |
| Retraso en juegos de reacción (¡Desenfunda!, Ritmo, Cronómetro) | En LAN es despreciable; si hace falta, el móvil manda la marca de tiempo de la pulsación. |
| Repo público | No hay secretos que guardar (Trystero no usa claves). La clave del Wi-Fi solo vive en la tele. |

## Fuera de alcance (de momento)

- Jugar con gente en otra casa (eso necesitaría ver la pantalla del host).
- Cuentas, ranking, partidas guardadas en la nube.
- Quitar DSU del APK.

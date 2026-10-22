# javiParty

Juego party de minijuegos para Android TV (y PC) en el que cada jugador usa **su móvil
como mando** mediante una app servidor DSU (protocolo cemuhook), p. ej. **DSU Controller**
en iPhone o Android. Godot 4.7, GDScript, renderer Compatibility, 1280x720.

## Ejecutar en PC (Linux)

```bash
sudo pacman -S godot          # Godot 4.7
godot --path . --import       # solo la primera vez (o abrir el proyecto en el editor)
godot --path .                # lanzar el juego
```

Controles en PC: flechas + Enter / Esc (igual que el mando de la tele), **F3** = overlay
de depuración.

## El mando de javiParty

Mando propio para DSU Controller (v3.0.6+), en horizontal: stick, cruceta, A, B, − HOME +.
Escanea con la app el QR `assets/controller/javiparty_qr.png` (o abre en el móvil el
enlace de `assets/controller/javiparty_link.txt`). Se regenera con
`python3 tools/make_layout.py [--size ANCHOxALTO]`.

El diseño Wiimote de la app también funciona (mismos bits para A y B).

## Conectar un móvil

1. Móvil y PC/tele en **la misma wifi** (no la de invitados).
2. Abre **DSU Controller** con el mando de javiParty y déjala en primer plano.
3. La pantalla de inicio busca sola en la red (cada 3 s) y el móvil aparece en una
   tarjeta de jugador. Si no aparece: **Añadir IP a mano** con la IP que muestra la app
   (puerto 26760). Las IPs manuales se recuerdan.
4. En los menús: cruceta para moverse, **A** acepta, **B** atrás, **HOME** abre el overlay.

Si no encuentra nada: wifi de invitados o aislamiento de clientes en el router, móvil
en otra red, app en segundo plano o ahorro de energía. En PC, un cortafuegos (`ufw`)
también puede bloquear las respuestas.

Hasta 4 jugadores. Si un móvil se desconecta conserva su hueco; al volver recupera
su jugador (por MAC, o por IP + slot).

## Sin móvil: simulador

```bash
python3 tools/dsu_simulator.py                 # 1 mando, controlado con el teclado
python3 tools/dsu_simulator.py --controllers 2 # varios mandos
python3 tools/dsu_simulator.py --auto          # se mueve solo
```

Ocupa el puerto 26760 del PC, así que el escáner lo encuentra como un móvil más.
Teclas: flechas = cruceta, z/x = A/B, -/+ , h = HOME (mismos bits que el mando de javiParty).

## Tests

```bash
python3 tools/gen_fixtures.py                           # regenera los paquetes de ejemplo
godot --headless --path . -s tests/run_tests.gd         # parseo DSU, CRC, mapeo de botones
python3 tools/dsu_simulator.py --auto &                 # integración: escaneo + datos reales
godot --headless --path . tests/e2e_scan.tscn
```

Los paquetes de ejemplo se generan con una implementación independiente en Python
(`struct` + `zlib.crc32`), así que los tests comparan dos implementaciones.

## Herramientas de diagnóstico

- `tools/dsu_probe.py`: guía para pulsar cada botón y hacer gestos; dice qué bit DSU
  manda cada botón de la app.
- `tools/dsu_gyro_probe.py`: deduce solo el mapeo de ejes del giroscopio moviendo el
  móvil libremente (compara la rotación de la gravedad con el giroscopio).

Ejecútalas en una terminal normal con javiParty cerrado.

## Estructura

```
net/        protocolo DSU (parseo/CRC), cliente UDP, escáner de red
input/      botones lógicos estilo Wiimote y diseños de cada app
core/       ajustes, jugadores, sonidos sintetizados
ui/         tema visual, pantalla de inicio, overlay de depuración
i18n/       textos en español e inglés
minigames/  un directorio por minijuego
tests/      tests headless + fixtures
tools/      simulador, sondas y generador de fixtures (Python, solo librería estándar)
```

## Notas técnicas

- **Un socket para datos, otro (en un hilo) para escanear.** `PacketPeerUDP.put_packet`
  es bloqueante: al mandar a 254 IPs que no existen, el kernel retiene los paquetes
  esperando a ARP, se llena el buffer y el envío se bloquea ~3 s. En el hilo principal
  eso congelaba el juego en cada barrido.
- **Botones**: el diseño Wiimote de DSU Controller manda la *posición* en el rombo, no
  la letra (A→bit "B", B→"Y", 1→"X", 2→"A"). Los minijuegos solo usan botones lógicos
  (`Pad.A`, `Pad.TWO`…). En sujeción horizontal la cruceta se rota 90°.

## Exportar a Android TV

Pendiente (fase 6).

## Licencias

Código propio. Fuente Nunito (SIL Open Font License, `assets/fonts/OFL.txt`).
Sonidos sintetizados por código. Sin assets de terceros.

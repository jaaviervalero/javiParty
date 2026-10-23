// Mando web de javiParty. Protocolo en docs/WEB.md.
// Fase 1: el juego (APK de la tele o escritorio) sirve esta página por HTTP y
// escucha el WebSocket en el puerto siguiente. Sin dependencias ni build.
"use strict";

// Botones lógicos: los mismos bits que Pad en el juego (input/pad.gd).
const BITS = { UP: 1, DOWN: 2, LEFT: 4, RIGHT: 8, A: 16, B: 32, "1": 64, "2": 128, "-": 256, "+": 512, HOME: 1024 };
const HEARTBEAT_MS = 500;
const RECONNECT_MS = [500, 1000, 2000, 3000];
const STICK_DEAD = 0.12;

const T = {
  es: {
    tapToPlay: "Toca para jugar", sameWifi: "Tienes que estar en el mismo Wi-Fi que la tele.",
    retry: "Reintentar", connecting: "Conectando…", reconnecting: "Se ha cortado. Reconectando…",
    full: "La partida está llena: ya hay 4 jugadores.", player: "Jugador %d",
    unreachable: "No llego al juego. ¿Estás en el mismo Wi-Fi que la tele?",
    ms: "%d ms", noNet: "sin conexión",
    // Por WebRTC (portátil): el enlace lleva la sala en el hash (#KQZT).
    laptopHint: "Escribe el código de 4 letras que sale en el portátil.",
    roomLabel: "Código de la partida", searching: "Buscando la partida…",
    noHost: "No encuentro la partida. ¿Está abierta en el portátil? Comprueba el código",
    badRoom: "El código son 4 letras (sin I ni O).",
  },
  en: {
    tapToPlay: "Tap to play", sameWifi: "You need to be on the same Wi-Fi as the TV.",
    retry: "Retry", connecting: "Connecting…", reconnecting: "Connection lost. Reconnecting…",
    full: "The game is full: there are already 4 players.", player: "Player %d",
    unreachable: "Can't reach the game. Are you on the same Wi-Fi as the TV?",
    ms: "%d ms", noNet: "offline",
    laptopHint: "Enter the 4-letter code shown on the laptop.",
    roomLabel: "Game code", searching: "Looking for the game…",
    noHost: "Can't find the game. Is it open on the laptop? Check the code",
    badRoom: "The code is 4 letters (no I or O).",
  },
};
const lang = (navigator.language || "es").slice(0, 2) === "en" ? "en" : "es";
const tr = (k, n) => T[lang][k].replace("%d", n);

const $ = (id) => document.getElementById(id);

// --- Identidad: id aleatorio guardado en el navegador (recargar = mismo jugador) ---
function deviceId() {
  try {
    let id = localStorage.getItem("javiparty-id");
    if (id) return id;
    id = randomId();
    localStorage.setItem("javiparty-id", id);
    return id;
  } catch (e) {
    // Modo privado o almacenamiento bloqueado: vale para esta pestaña.
    window.__jpId = window.__jpId || randomId();
    return window.__jpId;
  }
}
function randomId() {
  // crypto.randomUUID solo existe en https; getRandomValues también en http.
  const b = new Uint8Array(16);
  crypto.getRandomValues(b);
  return Array.from(b, (x) => x.toString(16).padStart(2, "0")).join("");
}

// --- Estado de entrada ---
const held = new Set();          // botones sueltos pulsados (A, B, 1, 2, -, +)
let dpadBits = 0;
let stick = { x: 0, y: 0 };
let seq = 0;
let lastSent = "";

function currentBits() {
  let b = dpadBits;
  for (const name of held) b |= BITS[name] || 0;
  return b;
}

function sendInput(force) {
  const msg = { t: "in", b: currentBits(), x: round2(stick.x), y: round2(stick.y) };
  const sig = msg.b + "," + msg.x + "," + msg.y;
  if (!force && sig === lastSent) return;
  lastSent = sig;
  msg.n = ++seq;
  send(msg);
}
const round2 = (v) => Math.round(v * 100) / 100;

// --- Conexión ---
// Dos transportes, mismos mensajes del protocolo:
//  - WebSocket: lo usa la tele/escritorio (página servida por http en la LAN).
//  - WebRTC: GitHub Pages (https) o cualquier enlace con #SALA; el apretón de
//    manos va por redes públicas con Trystero y luego el canal es directo.
const RTC_APP_ID = "javiparty";
const RTC_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ";
const RTC_HOST_WAIT_MS = 15000;
const RTC_HOST_GONE_MS = 4000;   // el host manda ping cada segundo
const RTC_HELLO_MS = 2000;
// Tras perder el host, si en este tiempo no vuelve, se sale de la sala y se
// entra de nuevo: Safari cierra en segundo plano las conexiones del apretón de
// manos y sin ellas no se puede volver a encontrar al host.
const RTC_REJOIN_MS = 3000;

function normalizeRoom(v) {
  const s = String(v || "").trim().toUpperCase();
  if (s.length !== 4) return "";
  for (const c of s) if (!RTC_ALPHABET.includes(c)) return "";
  return s;
}
const hashRoom = normalizeRoom(location.hash.replace(/^#/, ""));
let mode = (hashRoom || location.protocol === "https:") ? "rtc" : "ws";
let roomCode = hashRoom;

let ws = null;
let connectedOnce = false;
let attempts = 0;
let heartbeat = null;
let wantConnection = false;

// Estado del transporte WebRTC (null si no se está usando).
let rtc = null;
let rtcGen = 0;

function wsUrl() {
  const q = new URLSearchParams(location.search);
  const port = q.get("ws") || String((parseInt(location.port || "80", 10) || 80) + 1);
  return "ws://" + location.hostname + ":" + port;
}

function connect() {
  wantConnection = true;
  const waiting = mode === "rtc" ? tr("searching") : tr("connecting");
  showStatus(connectedOnce ? tr("reconnecting") : waiting, false);
  if (mode === "rtc") connectRtc(); else connectWs();
}

function connectWs() {
  wantConnection = true;
  showStatus(connectedOnce ? tr("reconnecting") : tr("connecting"), false);
  try {
    ws = new WebSocket(wsUrl());
  } catch (e) {
    return scheduleReconnect();
  }
  ws.onopen = () => {
    attempts = 0;
    send({ t: "hello", id: deviceId(), v: 1 });
  };
  ws.onmessage = (ev) => {
    let msg;
    try { msg = JSON.parse(ev.data); } catch (e) { return; }
    onMessage(msg);
  };
  ws.onclose = () => {
    stopHeartbeat();
    setNet(false);
    if (wantConnection) scheduleReconnect();
  };
  ws.onerror = () => {};
}

function scheduleReconnect() {
  const wait = RECONNECT_MS[Math.min(attempts, RECONNECT_MS.length - 1)];
  attempts++;
  if (attempts > 6 && !connectedOnce) {
    showStatus(tr("unreachable"), true);
    wantConnection = false;
    return;
  }
  showStatus(connectedOnce ? tr("reconnecting") : tr("connecting"), false);
  setTimeout(() => { if (wantConnection) connect(); }, wait);
}

function send(msg) {
  if (mode === "rtc") { rtcSend(msg); return; }
  if (ws && ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify(msg));
}

// --- WebRTC (Trystero) ---
function loadTrystero() {
  // En el despliegue trystero.js se copia junto a esta página; en el repo vive
  // en web/vendor/ (para poder probar con python -m http.server).
  return import("./trystero.js").catch(() => import("../vendor/trystero.js"));
}

function connectRtc() {
  const code = roomCode || hashRoom ||
    normalizeRoom($("roomInput") ? $("roomInput").value : "");
  if (!code) {
    wantConnection = false;
    showStatus(tr("badRoom"), true);
    return;
  }
  roomCode = code;
  stopRtc();
  const st = { room: code, entries: [], hostId: null, hostName: "", helloTimer: null, waitTimer: null, watchTimer: null, lastHost: 0 };
  rtc = st;
  const gen = ++rtcGen;
  loadTrystero().then((mod) => {
    if (gen !== rtcGen || rtc !== st || !wantConnection) return;
    startRtcRooms(mod, st);
  }).catch(() => {
    if (gen !== rtcGen || rtc !== st) return;
    wantConnection = false;
    stopRtc();
    showStatus(tr("unreachable"), true);
  });
}

function startRtcRooms(mod, st) {
  // Las dos estrategias a la vez: si una red pública falla, la otra sigue.
  const strategies = [["nostr", mod.joinNostr], ["torrent", mod.joinTorrent]];
  for (const [name, join] of strategies) {
    if (typeof join !== "function") continue;
    try {
      const room = join({ appId: RTC_APP_ID }, st.room);
      const entry = { name: name, room: room, action: null };
      entry.action = room.makeAction("m", {
        onMessage: (data, ctx) => rtcMessage(st, name, data, ctx.peerId),
      });
      room.onPeerJoin = (id) => {
        if (rtc !== st) return;
        rtcHelloTo(entry, id);
        armHostWait(st);   // hay gente: damos otros 15 s a que conteste el host
      };
      room.onPeerLeave = (id) => { if (rtc === st) rtcPeerLeave(st, id); };
      st.entries.push(entry);
    } catch (e) { /* esa estrategia no está disponible */ }
  }
  if (st.entries.length === 0) {
    wantConnection = false;
    stopRtc();
    showStatus(tr("unreachable"), true);
    return;
  }
  st.helloTimer = setInterval(() => rtcHelloAll(st), RTC_HELLO_MS);
  // Vigilante: el host manda ping cada segundo. Si se calla, se ha ido (WebRTC
  // tarda mucho en dar el canal por muerto por su cuenta).
  st.watchTimer = setInterval(() => {
    if (rtc !== st || !st.hostId) return;
    if (Date.now() - st.lastHost > RTC_HOST_GONE_MS) hostLost(st);
  }, 1000);
  rtcHelloAll(st);
  armHostWait(st);
}

function helloText() { return JSON.stringify({ t: "hello", id: deviceId(), v: 1 }); }

// Mientras no haya host, el hello va a todos: solo el host contesta welcome.
function rtcHelloTo(entry, id) {
  const st = rtc;
  if (!st || st.hostId) return;
  try { entry.action.send(helloText(), { target: id }).catch(() => {}); } catch (e) {}
}

function rtcHelloAll(st) {
  if (rtc !== st || st.hostId || !wantConnection) return;
  for (const entry of st.entries) {
    let ids = [];
    try { ids = Object.keys(entry.room.getPeers()); } catch (e) {}
    for (const id of ids) rtcHelloTo(entry, id);
  }
}

function armHostWait(st) {
  if (!st) return;
  clearTimeout(st.waitTimer);
  st.waitTimer = setTimeout(() => {
    if (rtc !== st || st.hostId || !wantConnection) return;
    if (connectedOnce) {
      // Ya jugábamos en esta sala: la partida existe, no hay que rendirse.
      connectRtc();
      return;
    }
    wantConnection = false;
    stopHeartbeat();
    stopRtc();
    showStatus(tr("noHost"), true);
  }, RTC_HOST_WAIT_MS);
}

function rtcMessage(st, name, data, from) {
  if (rtc !== st) return;
  let msg;
  try { msg = JSON.parse(typeof data === "string" ? data : JSON.stringify(data)); } catch (e) { return; }
  if (!st.hostId) {
    // Los mandos también se ven entre sí: solo hacemos caso al que dice ser host.
    if (msg.t !== "welcome" && msg.t !== "full") return;
    st.hostId = from;
    st.hostName = name;
    clearInterval(st.helloTimer); st.helloTimer = null;
    clearTimeout(st.waitTimer); st.waitTimer = null;
  } else if (from !== st.hostId) {
    return;  // ya tenemos host; los demás peers no nos interesan
  }
  st.lastHost = Date.now();
  onMessage(msg);
}

function rtcSend(msg) {
  const st = rtc;
  if (!st || !st.hostId) return;
  // El mismo peer físico puede estar en las dos estrategias: usa la que aún lo
  // tenga activo, y si no, la que lo vio primero.
  let entry = null;
  for (const e of st.entries) {
    try {
      if (e.room.getPeers()[st.hostId]) { entry = e; break; }
    } catch (err) {}
  }
  if (!entry) entry = st.entries.find((e) => e.name === st.hostName);
  if (!entry) return;
  try { entry.action.send(JSON.stringify(msg), { target: st.hostId }).catch(() => {}); } catch (e) {}
}

function hostLost(st) {
  if (rtc !== st || !st.hostId) return;
  st.hostId = null;
  st.hostName = "";
  stopHeartbeat();
  setNet(false);
  if (!wantConnection) return;
  showStatus(tr("reconnecting"), false);
  if (!st.helloTimer) st.helloTimer = setInterval(() => rtcHelloAll(st), RTC_HELLO_MS);
  rtcHelloAll(st);
  armHostWait(st);
  clearTimeout(st.rejoinTimer);
  st.rejoinTimer = setTimeout(() => {
    if (rtc === st && !st.hostId && wantConnection) connectRtc();
  }, RTC_REJOIN_MS);
}

function rtcPeerLeave(st, id) {
  if (id !== st.hostId) return;
  // Si solo ha caído una estrategia, el host sigue por la otra: no es un corte.
  for (const entry of st.entries) {
    try { if (entry.room.getPeers()[id]) return; } catch (e) {}
  }
  hostLost(st);
}

function stopRtc() {
  rtcGen++;
  const st = rtc;
  rtc = null;
  if (!st) return;
  clearInterval(st.helloTimer);
  clearInterval(st.watchTimer);
  clearTimeout(st.waitTimer);
  clearTimeout(st.rejoinTimer);
  for (const entry of st.entries) {
    try {
      const p = entry.room.leave();
      if (p && p.catch) p.catch(() => {});
    } catch (e) {}
  }
  st.entries = [];
}

// --- Pantalla encendida en https (Wake Lock; NoSleep si ya estuviera cargado) ---
let wakeLock = null;
let noSleep = null;
function keepAwake() {
  if (navigator.wakeLock) {
    if (wakeLock) return;
    navigator.wakeLock.request("screen").then((lock) => {
      wakeLock = lock;
      lock.addEventListener("release", () => { wakeLock = null; });
    }).catch(() => {});
  } else if (window.NoSleep) {
    try {
      noSleep = noSleep || new window.NoSleep();
      noSleep.enable();
    } catch (e) {}
  }
}

function onMessage(msg) {
  switch (msg.t) {
    case "welcome":
      connectedOnce = true;
      setPlayer(msg.player, msg.color);
      showPad();
      setNet(true);
      keepAwake();
      startHeartbeat();
      sendInput(true);
      break;
    case "full":
      wantConnection = false;
      showStatus(tr("full"), true);
      if (mode === "rtc") stopRtc();
      else if (ws) ws.close();
      break;
    case "layout":
      applyLayout(msg.controls || []);
      break;
    case "vibrate":
      buzz(msg.ms || 60);
      break;
    case "ping":
      send({ t: "pong", n: msg.n });
      break;
  }
}

function startHeartbeat() {
  stopHeartbeat();
  // Latido: el juego da el mando por perdido si en 3 s no llega nada.
  heartbeat = setInterval(() => sendInput(true), HEARTBEAT_MS);
}
function stopHeartbeat() { if (heartbeat) clearInterval(heartbeat); heartbeat = null; }

// --- Pantallas ---
function showStatus(text, canRetry) {
  $("start").classList.add("hidden");
  $("pad").classList.add("hidden");
  $("status").classList.remove("hidden");
  $("statusText").textContent = text;
  $("retryBtn").classList.toggle("hidden", !canRetry);
  document.querySelector("#status .spinner").classList.toggle("hidden", canRetry);
}
function showPad() {
  $("start").classList.add("hidden");
  $("status").classList.add("hidden");
  $("pad").classList.remove("hidden");
}
function setPlayer(n, color) {
  document.documentElement.style.setProperty("--player", color || "#33b5e5");
  $("badgeNum").textContent = n;
  $("playerName").textContent = tr("player", n);
  document.title = "javiParty · " + tr("player", n);
}
function setNet(ok) {
  $("net").classList.toggle("bad", !ok);
  $("net").textContent = ok ? "" : tr("noNet");
}

// --- Mando contextual: el juego dice qué botones hacen falta ---
function applyLayout(controls) {
  const names = controls.map((c) => c[0]);
  const labels = {};
  for (const c of controls) labels[c[0]] = c[1] || "";
  const useStick = names.includes("stick");
  const useDpad = !useStick && names.some((n) => ["dpad", "UP", "DOWN", "LEFT", "RIGHT"].includes(n));
  $("stick").classList.toggle("hidden", !useStick);
  $("dpad").classList.toggle("hidden", !useDpad);
  $("leftLabel").textContent = useStick ? labels.stick : (labels.dpad || "");
  // A siempre (listo / continuar); el resto solo si el juego los usa.
  const face = ["A", "B", "1", "2"];
  let shown = 0;
  for (const n of face) {
    const on = n === "A" || names.includes(n);
    document.querySelector(".slot-" + n.toLowerCase()).classList.toggle("hidden", !on);
    const lab = document.querySelector('.label[data-for="' + n + '"]');
    if (lab) lab.textContent = labels[n] || "";
    if (on) shown++;
  }
  document.querySelector(".face").classList.toggle("solo", shown === 1);
  // Sin cruceta ni stick, la mitad izquierda sobra.
  document.querySelector(".left").classList.toggle("hidden", !useStick && !useDpad);
  // Soltar todo lo que ya no se ve, para que no se quede pulsado.
  held.clear(); dpadBits = 0; stick = { x: 0, y: 0 }; resetKnob(); paintDpad();
  sendInput(true);
}

// --- Botones ---
function buzz(ms) { if (navigator.vibrate) try { navigator.vibrate(ms); } catch (e) {} }

for (const el of document.querySelectorAll("[data-btn]")) {
  const name = el.dataset.btn;
  const down = (e) => {
    e.preventDefault();
    try { el.setPointerCapture(e.pointerId); } catch (_) {}
    held.add(name); el.classList.add("on"); buzz(8); sendInput();
  };
  const up = (e) => {
    e.preventDefault();
    held.delete(name); el.classList.remove("on"); sendInput();
  };
  el.addEventListener("pointerdown", down);
  el.addEventListener("pointerup", up);
  el.addEventListener("pointercancel", up);
  el.addEventListener("lostpointercapture", up);
}

// --- Cruceta: la dirección sale del ángulo del dedo respecto al centro (8 sectores) ---
const dpad = $("dpad");
let dpadPointer = null;
function dpadFrom(e) {
  const r = dpad.getBoundingClientRect();
  const dx = e.clientX - (r.left + r.width / 2);
  const dy = e.clientY - (r.top + r.height / 2);
  if (Math.hypot(dx, dy) < r.width * 0.12) return 0;   // zona muerta en el centro
  const sector = Math.round(Math.atan2(dy, dx) / (Math.PI / 4));  // -4..4, 0 = derecha
  const dirs = { 0: BITS.RIGHT, 1: BITS.RIGHT | BITS.DOWN, 2: BITS.DOWN, 3: BITS.DOWN | BITS.LEFT,
    4: BITS.LEFT, "-4": BITS.LEFT, "-3": BITS.LEFT | BITS.UP, "-2": BITS.UP, "-1": BITS.UP | BITS.RIGHT };
  return dirs[sector] || 0;
}
function paintDpad() {
  for (const [cls, bit] of [["up", BITS.UP], ["down", BITS.DOWN], ["left", BITS.LEFT], ["right", BITS.RIGHT]]) {
    dpad.querySelector(".arrow." + cls).classList.toggle("on", (dpadBits & bit) !== 0);
  }
}
dpad.addEventListener("pointerdown", (e) => {
  e.preventDefault();
  dpadPointer = e.pointerId;
  try { dpad.setPointerCapture(e.pointerId); } catch (_) {}
  const b = dpadFrom(e);
  if (b !== dpadBits) { dpadBits = b; buzz(8); paintDpad(); sendInput(); }
});
dpad.addEventListener("pointermove", (e) => {
  if (e.pointerId !== dpadPointer) return;
  const b = dpadFrom(e);
  if (b !== dpadBits) { dpadBits = b; buzz(6); paintDpad(); sendInput(); }
});
const dpadUp = (e) => {
  if (e.pointerId !== dpadPointer) return;
  dpadPointer = null; dpadBits = 0; paintDpad(); sendInput();
};
dpad.addEventListener("pointerup", dpadUp);
dpad.addEventListener("pointercancel", dpadUp);
dpad.addEventListener("lostpointercapture", dpadUp);

// --- Stick: el centro es el centro de la base; radio = media base ---
const stickEl = $("stick");
const knob = $("knob");
let stickPointer = null;
function stickFrom(e) {
  const r = stickEl.getBoundingClientRect();
  const rad = r.width / 2;
  let x = (e.clientX - (r.left + rad)) / rad;
  let y = (e.clientY - (r.top + rad)) / rad;
  const len = Math.hypot(x, y);
  if (len > 1) { x /= len; y /= len; }
  if (len < STICK_DEAD) { x = 0; y = 0; }
  knob.style.transform = "translate(calc(-50% + " + (x * rad * 0.62) + "px), calc(-50% + " + (y * rad * 0.62) + "px))";
  return { x, y };   // y hacia abajo, como en Godot
}
function resetKnob() { knob.style.transform = "translate(-50%, -50%)"; }
stickEl.addEventListener("pointerdown", (e) => {
  e.preventDefault();
  stickPointer = e.pointerId;
  try { stickEl.setPointerCapture(e.pointerId); } catch (_) {}
  stick = stickFrom(e); sendInput();
});
stickEl.addEventListener("pointermove", (e) => {
  if (e.pointerId !== stickPointer) return;
  stick = stickFrom(e); sendInput();
});
const stickUp = (e) => {
  if (e.pointerId !== stickPointer) return;
  stickPointer = null; stick = { x: 0, y: 0 }; resetKnob(); sendInput();
};
stickEl.addEventListener("pointerup", stickUp);
stickEl.addEventListener("pointercancel", stickUp);
stickEl.addEventListener("lostpointercapture", stickUp);

// Nada de menús contextuales, zoom con dos dedos ni scroll.
document.addEventListener("contextmenu", (e) => e.preventDefault());
document.addEventListener("gesturestart", (e) => e.preventDefault());
document.addEventListener("touchmove", (e) => e.preventDefault(), { passive: false });

// Si la pestaña vuelve a primer plano, reconectar enseguida.
document.addEventListener("visibilitychange", () => {
  if (document.visibilityState === "visible") {
    keepAwake();
    if (mode === "rtc") {
      // Al volver del segundo plano las conexiones pueden estar muertas aunque
      // no lo parezca: sin noticias recientes del host, se entra de nuevo.
      const stale = !rtc || !rtc.hostId || Date.now() - rtc.lastHost > 2000;
      if ((wantConnection || connectedOnce) && stale) { wantConnection = true; connect(); }
    } else if (connectedOnce && (!ws || ws.readyState > 1)) {
      attempts = 0; wantConnection = true; connect();
    }
  } else {
    // Al bloquear el móvil, soltar todo para que no se quede un botón pulsado.
    held.clear(); dpadBits = 0; stick = { x: 0, y: 0 }; resetKnob(); paintDpad(); sendInput(true);
  }
});

// --- Arranque ---
for (const el of document.querySelectorAll("[data-i18n]")) el.textContent = T[lang][el.dataset.i18n];
document.documentElement.lang = lang;

if (mode === "rtc") {
  // Sin #SALA en el enlace, se pide el código a mano.
  $("roomBox").classList.toggle("hidden", !!roomCode);
  if (roomCode) $("roomInput").value = roomCode;
  $("startHint").textContent = T[lang].laptopHint;
} else {
  $("roomBox").classList.add("hidden");
}

$("startBtn").addEventListener("click", () => {
  if (mode === "rtc") {
    const typed = normalizeRoom($("roomInput").value);
    if (typed) {
      roomCode = typed;
      if (normalizeRoom(location.hash.replace(/^#/, "")) !== typed) {
        try { history.replaceState(null, "", "#" + typed); } catch (e) {}
      }
    } else if (!roomCode) {
      $("startHint").textContent = T[lang].badRoom;
      return;
    }
  }
  // El primer toque permite vibrar, pantalla completa y mantener la pantalla.
  const fs = document.documentElement.requestFullscreen;
  if (fs) fs.call(document.documentElement).catch(() => {});
  buzz(20);
  keepAwake();
  connect();
});
$("retryBtn").addEventListener("click", () => { attempts = 0; connect(); });

// Código a mano: solo letras válidas, y Enter equivale al botón grande.
const roomInput = $("roomInput");
roomInput.addEventListener("input", () => {
  const clean = roomInput.value.toUpperCase()
    .split("").filter((c) => RTC_ALPHABET.includes(c)).join("").slice(0, 4);
  if (roomInput.value !== clean) roomInput.value = clean;
});
roomInput.addEventListener("keydown", (e) => {
  if (e.key === "Enter") { e.preventDefault(); $("startBtn").click(); }
});

// Mando de menús hasta que el juego diga otra cosa.
applyLayout([["dpad", ""], ["A", ""], ["B", ""]]);

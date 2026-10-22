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
  },
  en: {
    tapToPlay: "Tap to play", sameWifi: "You need to be on the same Wi-Fi as the TV.",
    retry: "Retry", connecting: "Connecting…", reconnecting: "Connection lost. Reconnecting…",
    full: "The game is full: there are already 4 players.", player: "Player %d",
    unreachable: "Can't reach the game. Are you on the same Wi-Fi as the TV?",
    ms: "%d ms", noNet: "offline",
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

// --- Conexión (WebSocket a la tele/PC; la fase 3 añade WebRTC) ---
let ws = null;
let connectedOnce = false;
let attempts = 0;
let heartbeat = null;
let wantConnection = false;

function wsUrl() {
  const q = new URLSearchParams(location.search);
  const port = q.get("ws") || String((parseInt(location.port || "80", 10) || 80) + 1);
  return "ws://" + location.hostname + ":" + port;
}

function connect() {
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
  if (ws && ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify(msg));
}

function onMessage(msg) {
  switch (msg.t) {
    case "welcome":
      connectedOnce = true;
      setPlayer(msg.player, msg.color);
      showPad();
      setNet(true);
      startHeartbeat();
      sendInput(true);
      break;
    case "full":
      wantConnection = false;
      showStatus(tr("full"), true);
      if (ws) ws.close();
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
  if (document.visibilityState === "visible" && connectedOnce && (!ws || ws.readyState > 1)) {
    attempts = 0; wantConnection = true; connect();
  } else if (document.visibilityState === "hidden") {
    // Al bloquear el móvil, soltar todo para que no se quede un botón pulsado.
    held.clear(); dpadBits = 0; stick = { x: 0, y: 0 }; resetKnob(); paintDpad(); sendInput(true);
  }
});

// --- Arranque ---
for (const el of document.querySelectorAll("[data-i18n]")) el.textContent = T[lang][el.dataset.i18n];
document.documentElement.lang = lang;

$("startBtn").addEventListener("click", () => {
  // El primer toque permite vibrar y pantalla completa (Android; el iPhone no la da).
  const fs = document.documentElement.requestFullscreen;
  if (fs) fs.call(document.documentElement).catch(() => {});
  buzz(20);
  connect();
});
$("retryBtn").addEventListener("click", () => { attempts = 0; connect(); });

// Mando de menús hasta que el juego diga otra cosa.
applyLayout([["dpad", ""], ["A", ""], ["B", ""]]);

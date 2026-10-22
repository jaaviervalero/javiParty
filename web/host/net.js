// Puente WebRTC del host HTML5 de javiParty (fase 3 de docs/WEB.md).
//
// Godot lo consume por el singleton JavaScript: llama a jpNet.poll() una vez por
// frame y recibe un JSON con los eventos pendientes. Tipos simples a propósito.
//
//   jpNet.start(sala)     une la sala por Nostr y por torrents a la vez
//   jpNet.poll()          -> "[{...}]" con connect/disconnect/msg y lo vacía
//   jpNet.send(peer, txt) manda texto (el JSON del protocolo) a un peer
//   jpNet.close(peer)     deja de hablarle y emite disconnect
//   jpNet.stop()          sale de la sala
//   jpNet.status()        "off" | "connecting" | "ready" | "error:<motivo>"
//   jpNet.room()          sala abierta ("" si ninguna); para depurar
//
// Trystero va vendorizado en ./trystero.js (en el despliegue se copia junto a
// esta página). En el repo vive en web/vendor/, de ahí el segundo intento.

const APP_ID = "javiparty";
const ACTION = "m";

// Se prueban las dos estrategias a la vez: si una cae, la otra sigue.
const STRATEGIES = [
  ["nostr", "joinNostr"],
  ["torrent", "joinTorrent"],
];

let state = "off";
let currentRoom = "";
let startGen = 0;
let trysteroPromise = null;

let rooms = [];          // [{ name, room, action }]
let peerIds = new Map(); // peer int -> id de Trystero
let peers = new Map();   // id de Trystero -> peer int
let sources = new Map(); // id de Trystero -> Set(nombres de estrategia)
let ignored = new Set(); // ids a los que hemos dejado de hablar
let nextPeer = 1;
let events = [];

function loadTrystero() {
  if (!trysteroPromise) {
    trysteroPromise = import("./trystero.js")
      .catch(() => import("../vendor/trystero.js"));
  }
  return trysteroPromise;
}

function textOf(data) {
  if (typeof data === "string") return data;
  if (data instanceof ArrayBuffer) return new TextDecoder().decode(data);
  if (ArrayBuffer.isView(data)) return new TextDecoder().decode(data);
  try { return JSON.stringify(data); } catch (e) { return ""; }
}

function registerPeer(id, source) {
  if (ignored.has(id)) return;
  let set = sources.get(id);
  if (set) {
    set.add(source);
    return;  // ya lo vimos por otra estrategia
  }
  set = new Set([source]);
  sources.set(id, set);
  const peer = nextPeer++;
  peers.set(id, peer);
  peerIds.set(peer, id);
  events.push({ e: "connect", peer: peer, ip: "" });
}

function unregisterPeer(id, source) {
  const set = sources.get(id);
  if (!set) return;
  set.delete(source);
  if (set.size > 0) return;  // sigue vivo por la otra estrategia
  sources.delete(id);
  const peer = peers.get(id);
  peers.delete(id);
  if (peer === undefined) return;
  peerIds.delete(peer);
  events.push({ e: "disconnect", peer: peer });
}

function onPeerMessage(entry, data, peerId) {
  if (ignored.has(peerId)) return;
  if (!sources.has(peerId)) registerPeer(peerId, entry.name);
  if (!peers.has(peerId)) return;  // lo acabamos de ignorar
  events.push({ e: "msg", peer: peers.get(peerId), text: textOf(data) });
}

function initRooms(mod) {
  const failures = [];
  for (const [name, exportName] of STRATEGIES) {
    try {
      const join = mod[exportName];
      if (typeof join !== "function") throw new Error("falta " + exportName);
      const room = join({ appId: APP_ID }, currentRoom);
      const entry = { name: name, room: room, action: null };
      entry.action = room.makeAction(ACTION, {
        onMessage: (data, ctx) => onPeerMessage(entry, data, ctx.peerId),
      });
      room.onPeerJoin = (id) => registerPeer(id, name);
      room.onPeerLeave = (id) => unregisterPeer(id, name);
      rooms.push(entry);
    } catch (e) {
      failures.push(name + ": " + ((e && e.message) || e));
    }
  }
  if (rooms.length === 0) {
    state = "error:" + (failures.join("; ") || "trystero");
  } else {
    state = "ready";
  }
}

function start(room) {
  room = String(room === undefined || room === null ? "" : room).trim().toUpperCase();
  if (!room) {
    state = "error:sala";
    return false;
  }
  if (state !== "off" && currentRoom === room && rooms.length > 0) return true;

  stop();
  currentRoom = room;
  state = "connecting";
  events = [];
  nextPeer = 1;
  const gen = ++startGen;

  if (typeof RTCPeerConnection === "undefined") {
    state = "error:sin WebRTC";
    return false;
  }
  loadTrystero().then((mod) => {
    if (gen !== startGen || state === "off") return;
    initRooms(mod);
  }).catch((e) => {
    if (gen !== startGen) return;
    state = "error:" + ((e && e.message) || e);
  });
  return true;
}

function poll() {
  const out = JSON.stringify(events);
  events = [];
  return out;
}

function send(peer, text) {
  peer = Number(peer) | 0;
  const id = peerIds.get(peer);
  if (id === undefined || ignored.has(id)) return false;
  const set = sources.get(id);
  if (!set) return false;
  text = typeof text === "string" ? text : String(text);
  const candidates = [];
  for (const name of set) {
    const entry = rooms.find((r) => r.name === name);
    if (entry && entry.action) candidates.push(entry);
  }
  if (candidates.length === 0) return false;
  // Basta con mandarlo por una estrategia: el canal físico es el mismo, y
  // mandarlo por las dos duplicaría el mensaje en el otro extremo. Si esa
  // estrategia ya no tiene al peer, se prueba la siguiente.
  let i = 0;
  const tryNext = () => {
    while (i < candidates.length) {
      const entry = candidates[i++];
      try {
        const p = entry.action.send(text, { target: id });
        if (p && p.catch) { p.catch(() => tryNext()); return true; }
        return true;
      } catch (e) { /* prueba la siguiente */ }
    }
    return false;
  };
  return tryNext();
}

function close(peer) {
  peer = Number(peer) | 0;
  const id = peerIds.get(peer);
  if (id === undefined) return;
  // No se ignora para siempre: por WebRTC no hay forma de "colgar" de verdad, y
  // si el móvil vuelve a hablar (tras un corte de unos segundos) tiene que poder
  // entrar otra vez; onPeerMessage lo da de alta como peer nuevo.
  sources.delete(id);
  peers.delete(id);
  peerIds.delete(peer);
  events.push({ e: "disconnect", peer: peer });
}

function stop() {
  startGen++;
  for (const entry of rooms) {
    try {
      const p = entry.room.leave();
      if (p && p.catch) p.catch(() => {});
    } catch (e) {}
  }
  rooms = [];
  peerIds = new Map();
  peers = new Map();
  sources = new Map();
  ignored = new Set();
  events = [];
  currentRoom = "";
  state = "off";
}

window.jpNet = {
  start: start,
  poll: poll,
  send: send,
  close: close,
  stop: stop,
  status: () => state,
  room: () => currentRoom,
};

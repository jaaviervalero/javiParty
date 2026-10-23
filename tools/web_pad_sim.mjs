#!/usr/bin/env node
// Móviles simulados para el mando web (protocolo en docs/WEB.md).
//
//   node tools/web_pad_sim.mjs --test [host:puerto]     comprobaciones automáticas
//   node tools/web_pad_sim.mjs --players 2 [host:puerto] móviles que pulsan A y mueven el stick
//
// host:puerto es el de la PÁGINA (por defecto 127.0.0.1:8080); el WebSocket va
// en el puerto siguiente, como en la página real. Necesita Node 22+ (WebSocket nativo).

const args = process.argv.slice(2);
const target = args.find((a) => /^[\w.-]+:\d+$/.test(a)) || "127.0.0.1:8080";
const [host, httpPort] = target.split(":");
const WS = `ws://${host}:${Number(httpPort) + 1}`;
const BITS = { UP: 1, DOWN: 2, LEFT: 4, RIGHT: 8, A: 16, B: 32 };

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const rid = () => Array.from(crypto.getRandomValues(new Uint8Array(16)), (x) => x.toString(16).padStart(2, "0")).join("");

// Un "móvil": abre el WebSocket, manda hello, contesta a los ping y guarda lo recibido.
function phone(id = rid()) {
  const p = { id, msgs: [], ws: null, seq: 0, beat: null };
  p.open = () => new Promise((resolve, reject) => {
    p.ws = new WebSocket(WS);
    p.ws.onopen = () => { p.ws.send(JSON.stringify({ t: "hello", id: p.id, v: 1 })); resolve(p); };
    p.ws.onerror = (e) => reject(new Error("no conecta a " + WS));
    p.ws.onmessage = (ev) => {
      const m = JSON.parse(ev.data);
      p.msgs.push(m);
      if (m.t === "ping" && !p.frozen) p.ws.send(JSON.stringify({ t: "pong", n: m.n }));
    };
    p.ws.onclose = () => { p.closed = true; clearInterval(p.beat); };
  });
  p.input = (b, x = 0, y = 0) => p.ws.readyState === 1 && p.ws.send(JSON.stringify({ t: "in", b, x, y, n: ++p.seq }));
  p.heartbeat = () => { p.beat = setInterval(() => p.input(0), 500); };
  p.close = () => { clearInterval(p.beat); p.ws.close(); };
  p.last = (t) => [...p.msgs].reverse().find((m) => m.t === t);
  return p;
}

async function waitFor(fn, ms = 2000) {
  const end = Date.now() + ms;
  while (Date.now() < end) { const v = fn(); if (v) return v; await sleep(25); }
  return null;
}

let ok = 0, bad = 0;
function check(cond, what) {
  if (cond) { ok++; console.log("  ok   " + what); } else { bad++; console.log("  FALLO " + what); }
}

async function test() {
  // 1) La página se sirve.
  for (const path of ["/", "/controller.js", "/style.css"]) {
    const r = await fetch(`http://${host}:${httpPort}${path}`).catch(() => null);
    const body = r ? await r.text() : "";
    check(r && r.status === 200 && body.length > 200, `GET ${path} -> ${r ? r.status : "sin respuesta"} (${body.length} B)`);
  }
  const r404 = await fetch(`http://${host}:${httpPort}/../../project.godot`).catch(() => null);
  check(r404 && r404.status === 404, "no sirve ficheros fuera de la página");

  // 2) Dos móviles: jugador 1 y 2, cada uno con su color.
  const a = await phone().open(); a.heartbeat();
  const b = await phone().open(); b.heartbeat();
  const wa = await waitFor(() => a.last("welcome"));
  const wb = await waitFor(() => b.last("welcome"));
  check(wa && wa.player === 1, `primer móvil = jugador ${wa && wa.player}`);
  check(wb && wb.player === 2, `segundo móvil = jugador ${wb && wb.player}`);
  check(wa && wb && wa.color !== wb.color, `colores distintos (${wa && wa.color} / ${wb && wb.color})`);
  check(await waitFor(() => a.last("layout")), "llega el mando de menús (layout)");
  check(await waitFor(() => a.last("ping"), 1500), "el juego manda ping");

  // 3) Recargar la página (misma id, conexión nueva) devuelve el mismo jugador.
  a.close();
  await sleep(200);
  const a2 = await phone(a.id).open(); a2.heartbeat();
  const wa2 = await waitFor(() => a2.last("welcome"));
  check(wa2 && wa2.player === 1, `al recargar vuelve a ser el jugador ${wa2 && wa2.player}`);
  check(!b.closed, "el otro móvil sigue conectado");

  // 4) La misma id en dos pestañas: se queda la nueva y la vieja se cierra.
  const a3 = await phone(a.id).open(); a3.heartbeat();
  const wa3 = await waitFor(() => a3.last("welcome"));
  check(wa3 && wa3.player === 1, "segunda pestaña del mismo móvil = mismo jugador");
  check(await waitFor(() => a2.closed), "la pestaña vieja se cierra");

  // 5) Hasta 4; el quinto recibe "full".
  const c = await phone().open(); c.heartbeat();
  const d = await phone().open(); d.heartbeat();
  const e = await phone().open(); e.heartbeat();
  const wd = await waitFor(() => d.last("welcome"));
  check(wd && wd.player === 4, `cuarto móvil = jugador ${wd && wd.player}`);
  check(await waitFor(() => e.last("full")), "el quinto recibe 'sala llena'");

  // 6) Basura: JSON roto e id inválida no tumban nada.
  const junk = new WebSocket(WS);
  await new Promise((r) => (junk.onopen = r));
  junk.send("esto no es json");
  junk.send(JSON.stringify({ t: "hello", id: "../../x" }));
  await sleep(300);
  check(!b.closed && !c.closed, "mensajes rotos no afectan a los demás");

  // 7) Un móvil bloqueado (no late ni contesta a los ping) se da por
  //    desconectado a los ~3 s y, al volver, recupera su hueco.
  clearInterval(c.beat);
  c.frozen = true;
  await sleep(3600);
  check(await waitFor(() => c.closed, 1000), "sin latido 3 s: el juego lo desconecta");
  const c2 = await phone(c.id).open(); c2.heartbeat();
  const wc2 = await waitFor(() => c2.last("welcome"));
  check(wc2 && wc2.player === 3, `y al volver recupera el jugador ${wc2 && wc2.player}`);

  for (const p of [a3, b, c2, d, e]) p.close();
  junk.close();
  console.log(`\n${ok} OK, ${bad} FALLOS`);
  process.exit(bad ? 1 : 0);
}

async function simulate(n) {
  const phones = [];
  for (let i = 0; i < n; i++) {
    const p = await phone().open();
    phones.push(p);
    const w = await waitFor(() => p.last("welcome") || p.last("full"));
    console.log(`móvil ${i + 1}:`, w ? JSON.stringify(w) : "sin respuesta");
  }
  let t = 0;
  setInterval(() => {
    t += 0.05;
    phones.forEach((p, i) => {
      const a = Math.random() < 0.02 ? BITS.A : 0;
      p.input(a, Math.round(Math.cos(t + i) * 80) / 100, Math.round(Math.sin(t * 0.7 + i) * 80) / 100);
    });
  }, 50);
}

const n = args.indexOf("--players");
if (args.includes("--test")) test().catch((e) => { console.error(e.message); process.exit(2); });
else simulate(n >= 0 ? Number(args[n + 1]) : 1).catch((e) => { console.error(e.message); process.exit(2); });

// Web de descarga: idioma, aviso en móviles, botón copiar y código de Downloader.
"use strict";

// Código corto de la app Downloader (go.aftvnews.com). Vacío = solo se enseña la URL.
const DOWNLOADER_CODE = "6071356";  // -> releases/latest/download/javiParty-androidtv.apk

const html = document.documentElement;
const langBtn = document.getElementById("lang");

function setLang(l) {
  html.lang = l;
  langBtn.textContent = l === "es" ? "EN" : "ES";
  try { localStorage.setItem("javiparty-lang", l); } catch (e) {}
}
let saved = null;
try { saved = localStorage.getItem("javiparty-lang"); } catch (e) {}
setLang(saved || ((navigator.language || "es").toLowerCase().startsWith("es") ? "es" : "en"));
langBtn.addEventListener("click", () => setLang(html.lang === "es" ? "en" : "es"));

// En un móvil, recordar que el juego va en la tele o el PC (el móvil es el mando).
const ua = navigator.userAgent;
const isPhone = /iPhone|iPod|Android.*Mobile/i.test(ua) || (/Android/i.test(ua) && !/TV|AFT|BRAVIA|SMART-TV/i.test(ua) && screen.width < 900);
const byId = (id) => document.getElementById(id);  // algunas piezas solo están en la portada
if (isPhone && byId("mobileNote")) byId("mobileNote").classList.remove("hidden");

// Botón "añadir el mando" de DSU Controller: solo tiene sentido abierto en el móvil.
if (!isPhone && byId("dsuLink")) byId("dsuLink").classList.add("hidden");

if (DOWNLOADER_CODE && byId("dlCode")) {
  document.getElementById("dlCodeValue").textContent = DOWNLOADER_CODE;
  document.getElementById("dlCode").classList.remove("hidden");
}

for (const btn of document.querySelectorAll("[data-copy]")) {
  btn.addEventListener("click", async () => {
    try {
      await navigator.clipboard.writeText(btn.dataset.copy);
      btn.classList.add("done");
      setTimeout(() => btn.classList.remove("done"), 1500);
    } catch (e) {}
  });
}

// Ver las capturas en grande.
const viewer = document.getElementById("viewer");
if (viewer && viewer.showModal) {
  const img = viewer.querySelector("img");
  for (const b of document.querySelectorAll(".shot")) {
    b.addEventListener("click", () => {
      img.src = b.dataset.full;
      img.alt = b.querySelector("img").alt;
      viewer.showModal();
    });
  }
  viewer.addEventListener("click", () => viewer.close());
}

// --- Animaciones al hacer scroll ---
const calm = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
const header = document.querySelector(".top");
const tv = document.querySelector(".screen");
let ticking = false;
function onScroll() {
  ticking = false;
  const y = window.scrollY;
  header.classList.toggle("scrolled", y > 8);
  if (tv && !calm && window.innerWidth > 860) tv.style.setProperty("--py", Math.round(y * -0.08) + "px");
}
window.addEventListener("scroll", () => {
  if (!ticking) { ticking = true; requestAnimationFrame(onScroll); }
}, { passive: true });
onScroll();

if (!calm && "IntersectionObserver" in window) {
  // Cada grupo entra en cascada: el retraso crece con la posición dentro de su padre.
  const groups = [
    ".how > h2", ".steps li", ".teaser", ".section-head", ".actions", ".card-section > details",
    ".card-section > .soon", ".faq > h2", ".faq details", ".share", ".games > h2", ".games-sub",
    ".game", ".back.center",
  ];
  const els = document.querySelectorAll(groups.join(","));
  const io = new IntersectionObserver((entries) => {
    for (const e of entries) {
      if (e.isIntersecting) { e.target.classList.add("in"); io.unobserve(e.target); }
    }
  }, { rootMargin: "0px 0px -8% 0px", threshold: 0.12 });
  for (const el of els) {
    const i = Array.prototype.indexOf.call(el.parentElement.children, el);
    // En la rejilla de juegos, la cascada va por columnas (4 por fila) para no esperar de más.
    const n = el.classList.contains("game") ? i % 4 : i;
    el.style.setProperty("--d", Math.min(n * 90, 360) + "ms");
    el.classList.add("reveal");
    io.observe(el);
  }
}

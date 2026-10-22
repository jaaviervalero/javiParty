// Web de descarga: idioma, aviso en móviles, botón copiar y código de Downloader.
"use strict";

// Código corto de la app Downloader (go.aftvnews.com). Vacío = solo se enseña la URL.
const DOWNLOADER_CODE = "";

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
if (isPhone) document.getElementById("mobileNote").classList.remove("hidden");

// Botón "añadir el mando" de DSU Controller: solo tiene sentido abierto en el móvil.
if (!isPhone) document.getElementById("dsuLink").classList.add("hidden");

if (DOWNLOADER_CODE) {
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

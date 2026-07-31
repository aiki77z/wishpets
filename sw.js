const CACHE_NAME = "svt-pets-ipad-memo-v1";
const ASSETS = [
  "./ipad.html",
  "./index.html",
  "./styles.css",
  "./ipad-memo.css",
  "./app.js",
  "./ipad-memo.js",
  "./pet-data.js",
  "./manifest.webmanifest",
  "./build/icon.ico",
  "./bboogyuli/run/final/spritesheet.webp",
  "./chandalee/final/spritesheet.webp",
  "./cherry/final/spritesheet.webp",
  "./doa/final/spritesheet.webp",
  "./foxdungee/final/spritesheet.webp",
  "./kimja/final/spritesheet.webp",
  "./nonver/final/spritesheet.webp",
  "./ocl/final/spritesheet.webp",
  "./ppyopuli/run/final/spritesheet.webp",
  "./shuasumi/final/spritesheet.webp",
  "./tamtam/final/spritesheet.webp",
  "./thepalee/final/spritesheet.webp",
  "./toram/final/spritesheet.webp"
];

self.addEventListener("install", (event) => {
  event.waitUntil(caches.open(CACHE_NAME).then((cache) => cache.addAll(ASSETS)));
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((key) => key !== CACHE_NAME).map((key) => caches.delete(key)))
    )
  );
  self.clients.claim();
});

self.addEventListener("fetch", (event) => {
  if (event.request.method !== "GET") return;
  event.respondWith(
    caches.match(event.request).then((cached) =>
      cached || fetch(event.request).then((response) => {
        const copy = response.clone();
        caches.open(CACHE_NAME).then((cache) => cache.put(event.request, copy));
        return response;
      })
    )
  );
});

// Renders the Roblox game icon + thumbnails for MASSIVE STORE: LOCUST.
//   node render.js   ->  icon.png (512x512), thumbnail_1.png / thumbnail_2.png (1920x1080)
// Everything is vector (SVG) in the game's Figma style: dark store, sign yellow, red tag, Oswald.
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const LOCUST = fs.readFileSync(path.join(__dirname, 'locust.svgpart'), 'utf8');
const Y = '#ffc61a', R = '#e0262d', INK = '#0a0c0f';
const PRODUCTS = ['#ffc61a', '#e0262d', '#3d8bff', '#4cd964', '#ff8a1f', '#f2f0ea', '#a66bff'];

// deterministic random
let seed = 7;
const rnd = () => ((seed = (seed * 16807) % 2147483647) / 2147483647);

// a store aisle in one-point perspective. w,h = canvas, vx,vy = vanishing point
function aisle(w, h, vx, vy, opts = {}) {
  seed = opts.seed || 7;
  const out = [];
  const floorY = h, ceilY = 0;
  // ceiling + floor
  out.push(`<rect width="${w}" height="${h}" fill="url(#bg)"/>`);
  out.push(`<polygon points="0,${floorY} ${w},${floorY} ${vx},${vy}" fill="url(#floor)"/>`);
  // ceiling light strips converging
  for (let i = 0; i < 9; i++) {
    const t = 1 - Math.pow(0.72, i + 1); // depth 0..1
    const y = ceilY + (vy - ceilY) * t;
    const half = (w * 0.09) * (1 - t);
    const thick = Math.max(1.5, 14 * (1 - t));
    out.push(`<rect x="${vx - half}" y="${y}" width="${half * 2}" height="${thick}" rx="${thick / 2}" fill="#fff4cf" opacity="${0.95 - t * 0.5}" filter="url(#glow)"/>`);
  }
  // shelves on both sides: slabs that shrink toward the vanishing point
  for (const side of [-1, 1]) {
    for (let i = 0; i < 7; i++) {
      const t0 = 1 - Math.pow(0.78, i), t1 = 1 - Math.pow(0.78, i + 1);
      const xa = side < 0 ? 0 + (vx - 0) * t0 : w - (w - vx) * t0;
      const xb = side < 0 ? 0 + (vx - 0) * t1 : w - (w - vx) * t1;
      const topA = ceilY + (vy - ceilY) * t0 + h * 0.18 * (1 - t0);
      const topB = ceilY + (vy - ceilY) * t1 + h * 0.18 * (1 - t1);
      const botA = floorY + (vy - floorY) * t0, botB = floorY + (vy - floorY) * t1;
      out.push(`<polygon points="${xa},${topA} ${xb},${topB} ${xb},${botB} ${xa},${botA}" fill="#14171c" stroke="#0b0d10" stroke-width="2"/>`);
      // shelf levels with products
      for (let k = 0; k < 5; k++) {
        const f = 0.12 + k * 0.19;
        const ya = topA + (botA - topA) * f, yb = topB + (botB - topB) * f;
        const ha = (botA - topA) * 0.13, hb = (botB - topB) * 0.13;
        const c = PRODUCTS[Math.floor(rnd() * PRODUCTS.length)];
        const fade = 0.2 + 0.55 * (1 - t0);
        out.push(`<polygon points="${xa},${ya} ${xb},${yb} ${xb},${yb + hb} ${xa},${ya + ha}" fill="${c}" opacity="${fade}"/>`);
        out.push(`<polygon points="${xa},${ya + ha} ${xb},${yb + hb} ${xb},${yb + hb + 3} ${xa},${ya + ha + 4}" fill="#3a3f48" opacity="${fade}"/>`);
      }
    }
  }
  // fog toward the end of the aisle
  out.push(`<rect width="${w}" height="${h}" fill="url(#fog)"/>`);
  return out.join('\n');
}

function defs(vx, vy, w, h) {
  return `<defs>
  <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#1b1f26"/><stop offset=".6" stop-color="#0b0d10"/><stop offset="1" stop-color="#060708"/></linearGradient>
  <linearGradient id="floor" x1="0" y1="1" x2="0" y2="0"><stop offset="0" stop-color="#2a2d33"/><stop offset="1" stop-color="#0d0f12"/></linearGradient>
  <radialGradient id="fog" cx="${vx / w}" cy="${vy / h}" r=".55"><stop offset="0" stop-color="#0c0e12" stop-opacity=".95"/><stop offset=".35" stop-color="#0c0e12" stop-opacity=".55"/><stop offset="1" stop-color="#0c0e12" stop-opacity="0"/></radialGradient>
  <radialGradient id="vig" cx=".5" cy=".5" r=".75"><stop offset=".55" stop-color="#000" stop-opacity="0"/><stop offset="1" stop-color="#000" stop-opacity=".85"/></radialGradient>
  <radialGradient id="beam" cx=".5" cy=".5" r=".5"><stop offset="0" stop-color="#fff1c8" stop-opacity=".35"/><stop offset="1" stop-color="#fff1c8" stop-opacity="0"/></radialGradient>
  <radialGradient id="redglow" cx=".5" cy=".5" r=".5"><stop offset="0" stop-color="${R}" stop-opacity=".55"/><stop offset="1" stop-color="${R}" stop-opacity="0"/></radialGradient>
  <linearGradient id="leftfade" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#000" stop-opacity=".92"/><stop offset=".55" stop-color="#000" stop-opacity=".6"/><stop offset="1" stop-color="#000" stop-opacity="0"/></linearGradient>
  <filter id="glow" x="-50%" y="-200%" width="200%" height="500%"><feGaussianBlur stdDeviation="6" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>
  <filter id="eyeglow" x="-300%" y="-300%" width="700%" height="700%"><feGaussianBlur stdDeviation="2.5" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>
  <filter id="locustfx" x="-60%" y="-30%" width="220%" height="160%">
    <feMorphology in="SourceAlpha" operator="dilate" radius="1.1" result="d"/>
    <feFlood flood-color="#ff4a2a" flood-opacity=".75"/><feComposite in2="d" operator="in" result="rim"/>
    <feGaussianBlur in="rim" stdDeviation="1.1" result="rimb"/>
    <feGaussianBlur in="SourceGraphic" stdDeviation="2.2" result="glow"/>
    <feMerge><feMergeNode in="rimb"/><feMergeNode in="glow"/><feMergeNode in="glow"/><feMergeNode in="SourceGraphic"/></feMerge>
  </filter>
  <filter id="shadow"><feDropShadow dx="0" dy="6" stdDeviation="10" flood-color="#000" flood-opacity=".7"/></filter>
</defs>`;
}

const locust = (x, y, scale) =>
  `<ellipse cx="${x}" cy="${y - 60 * scale}" rx="${60 * scale}" ry="${70 * scale}" fill="url(#redglow)"/>
   <g transform="translate(${x},${y}) scale(${scale})" filter="url(#locustfx)">${LOCUST}</g>`;

// shopping cart silhouette, x,y = bottom centre
const cart = (x, y, s) => `<g transform="translate(${x},${y}) scale(${s})" fill="none" stroke="#9aa1a8" stroke-width="3" stroke-linejoin="round" opacity=".9">
  <path d="M-60,-70 L60,-70 L50,-20 L-50,-20 Z" fill="#9aa1a8" fill-opacity=".12"/>
  ${[-40, -20, 0, 20, 40].map(i => `<line x1="${i}" y1="-70" x2="${i * 0.85}" y2="-20"/>`).join('')}
  <line x1="-56" y1="-50" x2="56" y2="-50"/><path d="M60,-70 L78,-86 L92,-86" stroke="${R}" stroke-width="5"/>
  <path d="M-50,-20 L-46,-6 M50,-20 L46,-6"/><circle cx="-44" cy="-2" r="5" fill="#111"/><circle cx="44" cy="-2" r="5" fill="#111"/></g>`;

// fonts embedded from ./fonts (Oswald 700, Roboto Mono 700, Montserrat 600 — OFL, Google Fonts)
const ff = (name, file, weight) => `@font-face{font-family:'${name}';font-weight:${weight};src:url(data:font/woff2;base64,${fs.readFileSync(path.join(__dirname, 'fonts', file)).toString('base64')}) format('woff2')}`;
const font = `<style>${ff('Oswald', 'Oswald.woff2', 700)}${ff('Roboto Mono', 'RobotoMono.woff2', 700)}${ff('Montserrat', 'Montserrat.woff2', 600)}</style>`;
const page = (w, h, body) => `<!doctype html><html><head><meta charset="utf-8">${font}<style>
  html,body{margin:0;width:${w}px;height:${h}px;overflow:hidden;background:${INK}}
  .stage{position:relative;width:${w}px;height:${h}px}
  svg{position:absolute;inset:0}
  .t{position:absolute;font-family:Oswald,sans-serif;font-weight:700;color:#f2f0ea;line-height:.95;letter-spacing:.01em}
  .mono{font-family:'Roboto Mono',monospace;font-weight:700;color:${Y};letter-spacing:.2em}
  .tag{position:absolute;background:${R};color:#fff;font-family:Oswald,sans-serif;font-weight:700;letter-spacing:.18em;border-radius:6px;display:flex;align-items:center}
  .tag i{display:block;border-radius:50%;background:${INK};margin-left:auto}
  .body{position:absolute;font-family:Montserrat,sans-serif;font-weight:600;color:#c9ced6}
  .pill{position:absolute;font-family:'Roboto Mono',monospace;font-weight:700;color:#0b0b0b;background:${Y};border-radius:6px;letter-spacing:.12em}
</style></head><body><div class="stage">${body}</div></body></html>`;

// ---------- ICON 512x512 ----------
function icon() {
  const w = 512, h = 512, vx = 256, vy = 250;
  const svg = `<svg width="${w}" height="${h}" viewBox="0 0 ${w} ${h}">${defs(vx, vy, w, h)}
    ${aisle(w, h, vx, vy, { seed: 11 })}
    ${locust(256, 362, 2.55)}
    <rect width="${w}" height="${h}" fill="url(#vig)"/>
  </svg>`;
  const body = `${svg}
    <div class="t" style="left:0;right:0;top:26px;text-align:center;font-size:58px;text-shadow:0 4px 18px #000">MASSIVE STORE</div>
    <div class="tag" style="left:96px;top:398px;width:320px;height:82px;font-size:62px;padding-left:26px;box-sizing:border-box;box-shadow:0 8px 30px #000a">LOCUST<i style="width:18px;height:18px;margin-right:22px"></i></div>`;
  return page(w, h, body);
}

// ---------- THUMBNAIL 1: the hunt ----------
function thumb1() {
  const w = 1920, h = 1080, vx = 1260, vy = 470;
  const svg = `<svg width="${w}" height="${h}" viewBox="0 0 ${w} ${h}">${defs(vx, vy, w, h)}
    ${aisle(w, h, vx, vy, { seed: 3 })}
    <ellipse cx="1180" cy="780" rx="560" ry="420" fill="url(#beam)"/>
    ${locust(1270, 760, 4.6)}
    ${cart(1640, 1010, 2.4)}
    <rect width="${w}" height="${h}" fill="url(#leftfade)"/>
    <rect width="${w}" height="${h}" fill="url(#vig)"/>
  </svg>`;
  const body = `${svg}
    <div class="mono" style="position:absolute;left:110px;top:150px;font-size:30px">OPEN 24/7 · NO EXIT</div>
    <div class="t" style="left:100px;top:200px;font-size:176px">MASSIVE<br>STORE</div>
    <div class="tag" style="left:110px;top:560px;width:520px;height:124px;font-size:96px;padding-left:36px;box-sizing:border-box">LOCUST<i style="width:26px;height:26px;margin-right:34px"></i></div>
    <div class="body" style="left:112px;top:730px;font-size:40px;width:760px;line-height:1.35">Loot by day. Build by night.<br>Don't make a sound.</div>
    <div class="pill" style="left:112px;top:880px;padding:14px 24px;font-size:28px">SOLO · PARTY · 1–12 PLAYERS</div>`;
  return page(w, h, body);
}

// ---------- THUMBNAIL 2: base & party ----------
function thumb2() {
  const w = 1920, h = 1080, vx = 960, vy = 430;
  // barricade of planks + a generator glow in the middle of the aisle
  const planks = [0, 1, 2, 3].map(i => `<rect x="${660 + (i % 2) * 14}" y="${600 + i * 64}" width="600" height="46" rx="6" fill="#8a5f30" stroke="#5a3c1c" stroke-width="4" transform="rotate(${i % 2 ? -3 : 2} 960 ${620 + i * 64})"/>`).join('');
  const nails = [0, 1, 2, 3].map(i => `<circle cx="690" cy="${623 + i * 64}" r="5" fill="#ccc"/><circle cx="1230" cy="${623 + i * 64}" r="5" fill="#ccc"/>`).join('');
  const people = [[-330, 1.0], [-170, 1.08], [190, 1.05], [340, 0.95]].map(([dx, s]) =>
    `<g transform="translate(${960 + dx},1080) scale(${s})" fill="#050607"><circle cx="0" cy="-330" r="44"/><path d="M-62,-280 Q0,-300 62,-280 L74,-60 L-74,-60Z"/><rect x="-60" y="-70" width="48" height="80" rx="16"/><rect x="12" y="-70" width="48" height="80" rx="16"/></g>`).join('');
  const svg = `<svg width="${w}" height="${h}" viewBox="0 0 ${w} ${h}">${defs(vx, vy, w, h)}
    ${aisle(w, h, vx, vy, { seed: 19 })}
    ${locust(960, 600, 2.2)}
    ${planks}${nails}
    <ellipse cx="960" cy="1000" rx="700" ry="260" fill="url(#beam)"/>
    ${people}
    <rect width="${w}" height="${h}" fill="url(#vig)"/>
  </svg>`;
  const body = `${svg}
    <div class="mono" style="position:absolute;left:0;right:0;top:70px;text-align:center;font-size:30px">MASSIVE STORE: LOCUST</div>
    <div class="t" style="left:0;right:0;top:120px;text-align:center;font-size:150px;text-shadow:0 8px 40px #000">LOOT · BUILD · SURVIVE</div>
    <div class="tag" style="left:735px;top:300px;width:450px;height:84px;font-size:52px;justify-content:center;letter-spacing:.12em">NIGHT 7<i style="display:none"></i></div>`;
  return page(w, h, body);
}

(async () => {
  const browser = await chromium.launch({ executablePath: process.env.CHROMIUM || undefined });
  const jobs = [['icon.png', 512, 512, icon()], ['thumbnail_1.png', 1920, 1080, thumb1()], ['thumbnail_2.png', 1920, 1080, thumb2()]];
  for (const [file, w, h, html] of jobs) {
    const page = await browser.newPage({ viewport: { width: w, height: h } });
    await page.setContent(html, { waitUntil: 'networkidle' });
    await page.evaluate(() => document.fonts.ready);
    await page.screenshot({ path: path.join(__dirname, file) });
    await page.close();
    console.log('wrote', file);
  }
  await browser.close();
})();

// Catalog-fx: the visual test card for lib.js's creative pack (render it after changing the pack):
//   styles/_swatch/render.sh catalog-fx --draft   → styles/_swatch/out/catalog-fx/sheet.png
// 0.0–2.4 s: one labelled cell per creative-pack helper — post effects, the four 2D transitions, particles,
//            kinetic type, text markers, colour, and the GLSL transitions at cell scale (all looping).
// 2.4–5.0 s: three GLSL transitions full frame (shockwave → lightLeak → warpMorph), then the end card.

let FXC = null, FXF = null, CELLS = null;

export async function setup(ctx, tokens, lib) {
  const A = lib.SAFE.action, cols = 6, rows = 4, gx = 18, gy = 50;
  const cw = (A.w - gx * (cols - 1)) / cols, ch = (A.h - 40 - gy * rows) / rows;
  const names = [
    "glow", "duotone", "lightLeak", "shimmer", "dissolve", "push",
    "blinds", "zoomDip", "particles drift", "particles rise", "confetti", "particles orbit",
    "kinetic rise", "kinetic wave", "kinetic cascade", "marker highlight", "marker circle", "marker underline",
    "harmony", "ramp", "shader dissolve", "shader glitch", "shader zoomBlur", "shader kaleido",
  ];
  CELLS = names.map((name, i) => ({ name, x: A.x0 + (i % cols) * (cw + gx), y: A.y0 + 40 + Math.floor(i / cols) * (ch + gy) + gy - 16, w: cw, h: ch }));
  // one small FX context per cell demo (cells share a size) + the full-frame ones at half resolution (SwiftShader
  // rasterises every pixel; half-size upscales cleanly and keeps the card quick to render)
  FXC = {};
  for (const n of ["dissolve", "glitch", "zoomBlur", "kaleido"]) FXC[n] = lib.shaderTransition(n, { width: Math.round(cw), height: Math.round(ch) });
  FXF = {};
  for (const n of ["shockwave", "lightLeak", "warpMorph"]) FXF[n] = lib.shaderTransition(n, { width: lib.W / 2, height: lib.H / 2 });
}

export function renderAt(t, ctx, tokens, lib) {
  const C = (k) => lib.color(tokens, k);
  const scene = (label, bg) => (x) => {
    x.fillStyle = bg; x.fillRect(0, 0, lib.W, lib.H);
    x.save(); x.globalAlpha = 0.1; x.fillStyle = C("ink");
    for (let i = 0; i < 8; i++) { x.beginPath(); x.arc((i * 379 + 190) % lib.W, (i * 613 + 120) % lib.H, 150, 0, lib.TAU); x.fill(); }
    x.restore();
    lib.setFont(x, tokens, "display", 230); x.fillStyle = C("ink");
    lib.drawText(x, label, lib.W / 2, lib.H / 2 + 80, { align: "center" });
    lib.setFont(x, tokens, "mono", 28);
    lib.drawText(x, "lib shaderTransition", lib.W / 2, lib.H / 2 + 170, { align: "center" });
  };
  const grid = (x) => cells(x, Math.min(t, 2.4), tokens, lib);
  const cut = (name, u, drawA, drawB) => {
    if (u <= 0) return drawA(ctx);
    if (u >= 1) return drawB(ctx);
    const a = lib.offscreen("fxfull_a", drawA), b = lib.offscreen("fxfull_b", drawB);
    ctx.drawImage(FXF[name].render(u, a, b), 0, 0, lib.W, lib.H);
  };
  if (t < 2.5) return grid(ctx);
  if (t < 3.2) return cut("shockwave", lib.seg(t, 2.5, 3.1), grid, scene("shockwave", C("a")));
  if (t < 3.9) return cut("lightLeak", lib.seg(t, 3.2, 3.8), scene("shockwave", C("a")), scene("light leak", C("b")));
  if (t < 4.6) return cut("warpMorph", lib.seg(t, 3.9, 4.5), scene("light leak", C("b")), scene("warp", C("c")));
  lib.cut(ctx, t >= 4.7 ? 1 : 0, scene("warp", C("c")), scene("end", C("d")));
}

function cells(ctx, t, tokens, lib) {
  const C = (k) => lib.color(tokens, k);
  ctx.fillStyle = C("bg"); ctx.fillRect(0, 0, lib.W, lib.H);
  lib.setFont(ctx, tokens, "mono", 26); ctx.fillStyle = C("ink");
  lib.drawText(ctx, `lib.js creative pack · t ${t.toFixed(2)}`, lib.SAFE.action.x0, lib.SAFE.action.y0 + 28);
  for (const c of CELLS) {
    ctx.save();
    ctx.beginPath(); ctx.rect(c.x, c.y, c.w, c.h); ctx.clip();
    ctx.fillStyle = "#808080"; ctx.fillRect(c.x, c.y, c.w, c.h);
    try { draw(c, ctx, t, tokens, lib); } finally { ctx.restore(); }
    ctx.strokeStyle = C("ink"); ctx.lineWidth = 2; ctx.strokeRect(c.x, c.y, c.w, c.h);
    lib.setFont(ctx, tokens, "mono", 19); ctx.fillStyle = C("ink");
    lib.drawText(ctx, c.name, c.x, c.y - 9);
  }
}

// Every cell loops inside its own period, so any sampled frame shows live content (and the card never freezes).
function draw(c, ctx, t, tokens, lib) {
  const C = (k) => lib.color(tokens, k), cx = c.x + c.w / 2, cy = c.y + c.h / 2;
  const cyc = (p, off = 0) => lib.fract(t / p + off) * p;                       // cycle-local time, loops at p
  // A mini "scene" the size of one cell. 2D-transition cells paint it at the cell's absolute position (they run on
  // the clipped main ctx); the shader cells paint it at (0,0) into cell-sized offscreens that become u_tex0/u_tex1.
  const mini = (x, ox, oy, bg, tag) => {
    x.fillStyle = bg; x.fillRect(ox, oy, c.w, c.h);
    lib.setFont(x, tokens, "display", 110); x.fillStyle = C("ink");
    lib.drawText(x, tag, ox + c.w / 2 + (tag === "A" ? -36 : 36), oy + c.h / 2 + 38, { align: "center" });
    lib.setFont(x, tokens, "mono", 21);
    lib.drawText(x, tag === "A" ? "scene A" : "scene B", ox + c.w / 2, oy + 32, { align: "center" });
  };
  const A = (x, bg) => mini(x, c.x, c.y, bg, "A");
  const B = (x, bg) => mini(x, c.x, c.y, bg, "B");
  const label = (word, size = 54) => { lib.setFont(ctx, tokens, "display", size); ctx.fillStyle = C("ink");
    return lib.layoutText(ctx, word, { x: cx, y: cy + size * 0.35, align: "center" }); };
  switch (c.name) {
    case "glow": {
      const src = lib.offscreen("cfx_glow", (x) => { x.fillStyle = "#0d1022"; x.fillRect(c.x, c.y, c.w, c.h);
        for (let i = 0; i < 3; i++) { const g = 18 + 10 * Math.sin(t * 2 + i * 2.1);
          x.fillStyle = ["#ffd166", "#ef476f", "#06d6a0"][i]; x.beginPath(); x.arc(cx + (i - 1) * 74, cy + Math.sin(t * 1.7 + i) * 26, g, 0, lib.TAU); x.fill(); } });
      ctx.drawImage(src, 0, 0);
      lib.glow(ctx, src, { radius: 30, strength: 0.85, threshold: 0.55 });
      break;
    }
    case "duotone": {
      const src = lib.offscreen("cfx_duo", (x) => { const g = x.createLinearGradient(c.x, c.y, c.x + c.w, c.y + c.h);
        g.addColorStop(0, "#fff"); g.addColorStop(1, "#000"); x.fillStyle = g; x.fillRect(c.x, c.y, c.w, c.h);
        lib.setFont(x, tokens, "display", 90); x.fillStyle = "#666"; lib.drawText(x, "双", cx + 40, cy + 30, { align: "center" }); });
      lib.duotone(ctx, src, { dark: "#1a2a5e", light: "#ffd9a0" });
      break;
    }
    case "lightLeak": {
      ctx.fillStyle = "#141821"; ctx.fillRect(c.x, c.y, c.w, c.h);
      lib.setFont(ctx, tokens, "display", 64); ctx.fillStyle = "#e8e2d5"; lib.drawText(ctx, "leak", cx, cy + 22, { align: "center" });
      lib.lightLeak(ctx, t, { amount: 0.85, seed: 3 });
      break;
    }
    case "shimmer": {
      const src = lib.offscreen("cfx_shim", (x) => { lib.setFont(x, tokens, "display", 76); x.fillStyle = "#2b2b33";
        lib.drawText(x, "SHINE", cx, cy + 26, { align: "center" }); });
      ctx.fillStyle = "#f6f2e7"; ctx.fillRect(c.x, c.y, c.w, c.h);
      ctx.drawImage(src, 0, 0);
      lib.shimmer(ctx, t, src, { period: 1.8, amount: 0.9, color: "#ffb238" });
      break;
    }
    case "dissolve": lib.dissolve(ctx, lib.ease.inOutSine(cyc(1.6) / 1.6), (x) => A(x, C("a")), (x) => B(x, C("b")), { cell: 20, seed: 5 }); break;
    case "push": lib.push(ctx, lib.ease.inOutCubic(cyc(1.6) / 1.6), (x) => A(x, C("b")), (x) => B(x, C("c")), { dir: [1, 0] }); break;
    case "blinds": lib.blinds(ctx, lib.ease.inOutCubic(cyc(1.8) / 1.8), (x) => A(x, C("c")), (x) => B(x, C("d")), { bands: 6, angle: 12, stagger: 0.6 }); break;
    case "zoomDip": lib.zoomDip(ctx, lib.ease.inOutCubic(cyc(2.0) / 2.0), (x) => A(x, C("d")), (x) => B(x, C("a")), { zoom: 1.35 }); break;
    case "particles drift":
      ctx.fillStyle = "#10141c"; ctx.fillRect(c.x, c.y, c.w, c.h);
      lib.particles(ctx, t, { mode: "drift", n: 70, seed: 11, area: c, size: [1.2, 3], color: "#cfd8ff", speed: 60, alpha: 0.55, twinkle: 0.6 });
      break;
    case "particles rise":
      ctx.fillStyle = "#170f0a"; ctx.fillRect(c.x, c.y, c.w, c.h);
      lib.particles(ctx, t, { mode: "rise", n: 60, seed: 3, area: c, size: [1, 3], color: "#ff9d4d", speed: 30, life: 1.8, twinkle: 0.5, spread: 0.7 });
      break;
    case "confetti":
      ctx.fillStyle = "#f4f0e6"; ctx.fillRect(c.x, c.y, c.w, c.h);
      lib.particles(ctx, t, { mode: "fall", n: 80, seed: 9, area: c, size: [2, 4.5], color: "#e4572e", speed: 30, life: 2.2, twinkle: 0 });
      break;
    case "particles orbit":
      ctx.fillStyle = "#0b0e1d"; ctx.fillRect(c.x, c.y, c.w, c.h);
      lib.particles(ctx, t, { mode: "orbit", n: 90, seed: 6, area: c, size: [1.2, 3.2], color: "#ffe9b0", speed: 40, twinkle: 0.7 });
      break;
    case "kinetic rise": {
      ctx.fillStyle = "#fbfaf7"; ctx.fillRect(c.x, c.y, c.w, c.h);
      lib.drawKinetic(ctx, label("RISE", 56), cyc(1.6), { mode: "rise", stagger: 0.06, dur: 0.5 });
      break;
    }
    case "kinetic wave": {
      ctx.fillStyle = "#fbfaf7"; ctx.fillRect(c.x, c.y, c.w, c.h);
      lib.drawKinetic(ctx, label("WAVE", 56), t, { mode: "wave", amp: 0.8 });
      break;
    }
    case "kinetic cascade": {
      ctx.fillStyle = "#fbfaf7"; ctx.fillRect(c.x, c.y, c.w, c.h);
      lib.drawKinetic(ctx, label("CASCADE", 44), cyc(1.7), { mode: "cascade", stagger: 0.045, dur: 0.55, amp: 0.6 });
      break;
    }
    case "marker highlight": {
      ctx.fillStyle = "#fbfaf7"; ctx.fillRect(c.x, c.y, c.w, c.h);
      const lay = label("KEY LINE", 46);
      lib.marker(ctx, lib.box(lay.x0, lay.y - lay.ascent, lay.x1, lay.y + lay.descent), cyc(1.8), { mode: "highlight", color: "#ffd400", draw: 0.3, hold: 0.5 });
      lib.drawKinetic(ctx, lay, t, { mode: "pop", stagger: 0.03, dur: 0.4 });   // settled after the first cycle
      break;
    }
    case "marker circle": {
      ctx.fillStyle = "#fbfaf7"; ctx.fillRect(c.x, c.y, c.w, c.h);
      const lay = label("FOCUS", 52);
      lib.drawKinetic(ctx, lay, t, { mode: "pop", stagger: 0.03, dur: 0.4 });
      lib.marker(ctx, lib.box(lay.x0, lay.y - lay.ascent, lay.x1, lay.y + lay.descent), cyc(1.8), { mode: "circle", color: "#e4572e", draw: 0.5, hold: 0.3 });
      break;
    }
    case "marker underline": {
      ctx.fillStyle = "#fbfaf7"; ctx.fillRect(c.x, c.y, c.w, c.h);
      const lay = label("POINTS", 46);
      lib.drawKinetic(ctx, lay, t, { mode: "pop", stagger: 0.03, dur: 0.4 });
      lib.marker(ctx, lib.box(lay.x0, lay.y - lay.ascent, lay.x1, lay.y + lay.descent), cyc(1.8), { mode: "underline", color: "#2a7de1", draw: 0.35, hold: 0.4 });
      break;
    }
    case "harmony": {
      ctx.fillStyle = "#fbfaf7"; ctx.fillRect(c.x, c.y, c.w, c.h);
      const cols = lib.harmony(C("c"), { scheme: "analogous", count: 5, seed: 2 });
      const sw = (c.w - 60) / 5;
      for (let i = 0; i < 5; i++) { ctx.fillStyle = cols[i]; ctx.fillRect(c.x + 30 + i * sw, cy - 34, sw - 8, 68); }
      lib.setFont(ctx, tokens, "mono", 20); ctx.fillStyle = C("ink");
      lib.drawText(ctx, cols[0], cx, c.y + 30, { align: "center" });
      break;
    }
    case "ramp": {
      ctx.fillStyle = "#fbfaf7"; ctx.fillRect(c.x, c.y, c.w, c.h);
      const stops = [[0, "#0a0e2a"], [0.45, "#5b2a86"], [0.75, "#c94f7c"], [1, "#ff9a3c"]];
      for (let i = 0; i < 52; i++) { const u = i / 51; ctx.fillStyle = lib.ramp(stops, u); ctx.fillRect(c.x + 26 + u * (c.w - 52), cy - 40, (c.w - 52) / 52 + 1, 80); }
      const u = lib.fract(t / 2.4), hx = lib.ramp(stops, u);
      ctx.fillStyle = "#fff"; ctx.strokeStyle = C("ink"); ctx.lineWidth = 2;
      ctx.beginPath(); ctx.arc(c.x + 26 + u * (c.w - 52), cy, 13, 0, lib.TAU); ctx.fill(); ctx.stroke();
      lib.setFont(ctx, tokens, "mono", 20); ctx.fillStyle = C("ink"); lib.drawText(ctx, hx, cx, c.y + c.h - 14, { align: "center" });
      break;
    }
    case "shader dissolve": case "shader glitch": case "shader zoomBlur": case "shader kaleido": {
      const n = c.name.replace("shader ", "");
      const a = lib.offscreen("cfx_fa", (x) => mini(x, 0, 0, C("a"), "A"), c.w, c.h);
      const b = lib.offscreen("cfx_fb", (x) => mini(x, 0, 0, C("b"), "B"), c.w, c.h);
      ctx.drawImage(FXC[n].render(lib.ease.inOutSine(cyc(1.7) / 1.7), a, b, { u_seed: 2 }), c.x, c.y);
      break;
    }
  }
}

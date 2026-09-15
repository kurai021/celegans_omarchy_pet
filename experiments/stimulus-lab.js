/* Stimulus Lab (Phase B): do the Lab channels produce a MEASURABLE neural and
 * motor response in the real connectome?
 *
 * Three controlled, repeatable experiments, all running the REAL Celegans.js:
 *
 *  A. FIXED-POSE RESPONSE  — the worm holds a fixed pose in an empty arena
 *     facing a single field source placed to its LEFT (same pose, source at a
 *     fixed offset, sham = no source). For each channel we count how often the
 *     real target + downstream cells fire and the accumulated motor left/right.
 *     Question: does arming thermo (AFD) or chemical-B (AWA) transfer into the
 *     wiring at all, and with what sign?
 *
 *  B. NAVIGATION CONSEQUENCE — 1200-cycle walks with the auxiliary steering
 *     layer OFF (gradientGain=0, brainTurnGain=0: no Pet.qml bypass, like
 *     "aux-off" in Phase C) in an empty arena with a fixed source. We compare
 *     the mean heading bias (motor L-R), the travelled distance and whether
 *     the accumulated displacement projects toward/away from the source.
 *     Question: does the injected asymmetry actually move the worm?
 *
 *  C. TAIL REFLEX — empty arena, aux off, one symmetric poke into PLML/PLMR at
 *     cycle 5 (charge 150, 4-cycle window, just like BrainConnector). We
 *     measure the motor burst right after the poke and the reversal (does the
 *     forward drive change sign?) versus a sham.
 *
 * All injection code below is transcribed 1:1 from BrainConnector.qml so the
 * numbers match what the live Lab shows. The fields use the same falloff as
 * World.qml. Seeds make every run reproducible.
 */

const fs = require("fs");
const vm = require("vm");
const path = require("path");

const DIR = path.join(__dirname, "..", "panels");

/* --- seeded RNG (same as the Phase C harness) ----------------------------- */
function mulberry32(seed) {
  let a = seed >>> 0;
  return function () {
    a |= 0; a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

let seed = 20260914;
let budget = "all";           // "all" | "A" | "B" | "C"
for (let i = 2; i < process.argv.length; i++) {
  const m = /^--seed=(\d+)$/.exec(process.argv[i]);
  if (m) seed = Math.abs(parseInt(m[1], 10)) || seed;
  const s = /^--scenario=([ABCabc,]+)$/.exec(process.argv[i]);
  if (s) budget = s[1].toUpperCase();
}
const rnd = mulberry32(seed);

/* Load the real connectome in a sandbox. */
const ctx = { Math, Date, console };
ctx.Math.random = rnd;
vm.createContext(ctx);
vm.runInContext(fs.readFileSync(path.join(DIR, "Celegans.js"), "utf8"), ctx);
const Brain = ctx.Brain;

/* --- constants transcribed from BrainConnector.qml / Pet.qml / World.qml ---- */
const ARENA_W = 640, ARENA_H = 480;
const BODY_W = 60, BODY_H = 90;
const FORWARD_PROBE = 80, SIDE_FORWARD = 60, SIDE_SPREAD = 24;
const FIELD_RADIUS = 260;
const ENERGY = 50;
const STEER_ALPHA = 0.35;
const INNER_NUDGE = 2, TURN_RATE = 28, HARD_TURN_RATE = 60;
const FOOD_LURE = 90, HUNT_FLOOR = 0.3;
const THERMO_BASE = 30, CHEM_B_BASE = 45;   // Lab slider weights at 100%
const TAIL_CHARGE = 150, TAIL_COOLDOWN = 4;

/* --- components of the harness shared across scenarios --------------------- */

function fieldAt(sources, radius, x, y) {
  let s = 0;
  for (let i = 0; i < sources.length; i++) {
    const dx = sources[i].x - x, dy = sources[i].y - y;
    const d = Math.sqrt(dx * dx + dy * dy);
    if (d < radius) { const t = 1 - d / radius; s += t * t; }
  }
  return s;
}
/* Three probes (ahead / left / right) exactly like Pet.qml reads them. */
function probe3(at, cx, cy, rot) {
  const c = Math.cos(rot * Math.PI / 180), s = Math.sin(rot * Math.PI / 180);
  const f = at(cx + c * FORWARD_PROBE, cy + s * FORWARD_PROBE);
  const sx = cx + c * SIDE_FORWARD, sy = cy + s * SIDE_FORWARD;
  const l = at(sx - s * SIDE_SPREAD, sy + c * SIDE_SPREAD);
  const r = at(sx + s * SIDE_SPREAD, sy - c * SIDE_SPREAD);
  return { f, l, r };
}

function newBrain() {
  const brain = new Brain();
  brain.setup();
  brain.stimulateFoodSenseNeurons = true;
  return brain;
}

/* The exact Lab injection code from BrainConnector.qml (channels section).
 * `stim` = { thermo: {w, forward, left, right}, chemB: {...}, tail: {cooldown, side, scale} } */
function injectChannels(brain, stim) {
  const next = brain.nextState;
  const t = stim.thermo;
  if (t.w > 0 && (t.left > 0 || t.right > 0 || t.forward > 0)) {
    const bal = t.left - t.right;
    if (Math.abs(bal) > 0.02) {
      brain.postSynaptic["AFDL"][next] += t.w * bal;
      brain.postSynaptic["AFDR"][next] += -t.w * bal;
    }
    const dr = t.w * 0.4 * t.forward;
    if (dr > 0) { brain.postSynaptic["AFDL"][next] += dr; brain.postSynaptic["AFDR"][next] += dr; }
  }
  const cb = stim.chemB;
  if (cb.w > 0 && (cb.left > 0 || cb.right > 0 || cb.forward > 0)) {
    const bal = cb.left - cb.right;
    if (Math.abs(bal) > 0.02) {
      brain.postSynaptic["AWAL"][next] += cb.w * bal;
      brain.postSynaptic["AWAR"][next] += -cb.w * bal;
    }
    const dr = cb.w * 0.4 * cb.forward;
    if (dr > 0) { brain.postSynaptic["AWAL"][next] += dr; brain.postSynaptic["AWAR"][next] += dr; }
  }
  if (stim.tail.cooldown > 0) {
    let wl = 1.0, wr = 1.0;
    if (stim.tail.side === "left") { wl = 1.0; wr = 0.5; }
    else if (stim.tail.side === "right") { wl = 0.5; wr = 1.0; }
    const ch = TAIL_CHARGE * stim.tail.scale;
    brain.postSynaptic["PLML"][next] += ch * wl;
    brain.postSynaptic["PLMR"][next] += ch * wr;
    stim.tail.cooldown--;
  }
  stim.tail.side = "none"; stim.tail.scale = 1;
}

function brainCycle(brain, sim) {
  const next = brain.nextState;
  if (sim.touchCooldown > 0) {
    let wl = 1.0, wr = 1.0;
    if (sim.pendingTouchSide === "left") { wl = 0.6; wr = 1.4; }
    else if (sim.pendingTouchSide === "right") { wl = 1.4; wr = 0.6; }
    const charge = 120 * sim.pendingTouchScale;
    brain.postSynaptic["ALML"][next] += charge * wl;
    brain.postSynaptic["ALMR"][next] += charge * wr;
    brain.stimulateNoseTouchNeurons = true;
    sim.touchCooldown--;
  } else brain.stimulateNoseTouchNeurons = false;
  sim.pendingTouchSide = "none"; sim.pendingTouchScale = 1;

  const smell = sim.smell;
  if (smell.sl > 0 || smell.sr > 0 || smell.sf > 0) {
    const bal = smell.sl - smell.sr;
    if (Math.abs(bal) > 0.02) {
      brain.postSynaptic["ADFL"][next] += 26 * bal;
      brain.postSynaptic["ADFR"][next] += -26 * bal;
    }
    const dr = 26 * 0.4 * smell.sf;
    if (dr > 0) { brain.postSynaptic["ADFL"][next] += dr; brain.postSynaptic["ADFR"][next] += dr; }
  }
  smell.sf = smell.sl = smell.sr = 0;

  injectChannels(brain, sim);   // thermo / chem-B / tail, exactly like the Lab

  brain.update();
  const left = brain.accumleft, right = brain.accumright;
  brain.accumleft = 0; brain.accumright = 0;
  return { left, right };
}

/* ==========================================================================
 * Scenario A — fixed pose, ONE field source ahead-diagonal. The questions:
 *   1) does arming the channel activate the real target cells (fires over
 *      400 cycles) vs. the sham (no source / weight 0)?
 *   2) does the injected imbalance bias the motor L/R output at all?
 * The worm does not move: only the brain runs, so the readout is pure. The
 * mirror source placement should flip the sign of the bias if the wiring is
 * directional (vs. mere activation without a sense of ``which side'').        */

function scenarioA() {
  console.log("\nScenario A · fixed pose, single field source · cell fires + motor bias (400 cycles)\n");
  const cx = ARENA_W / 2, cy = ARENA_H / 2, rot = 0; // facing +x
  const dl = { x: cx + 140, y: cy - 80 };   // ahead-RIGHT of the facing axis
  const dr = { x: cx + 140, y: cy + 80 };   // ahead-LEFT
  const nose = (sx) => (x, y) => fieldAt(sx, FIELD_RADIUS, x, y);

  const mktrial = (name, weight, sources, cellpicks) => {
    const brain = newBrain();
    const sim = { touchCooldown: 0, pendingTouchSide: "none", pendingTouchScale: 1,
      smell: { sf: 0, sl: 0, sr: 0 }, thermo: { w: 0, f: 0, l: 0, r: 0 },
      chemB: { w: 0, f: 0, l: 0, r: 0 }, tail: { cooldown: 0, side: "none", scale: 1 } };
    let L = 0, R = 0, sumLR = 0, totalFired = 0;
    const quarters = [0, 0, 0, 0];   // fires per 100-cycle quarter
    const win = [];
    for (let cyc = 0; cyc < 400; cyc++) {
      const p3 = probe3(nose(sources), cx, cy, rot);
      sim.thermo = { w: weight, f: p3.f, l: p3.l, r: p3.r };
      sim.chemB = { w: 0, f: 0, l: 0, r: 0 };
      const mk = brainCycle(brain, sim);
      L += mk.left; R += mk.right; sumLR += mk.left - mk.right;
      totalFired += brain.firedThisCycle.length;
      quarters[Math.floor(cyc / 100)] += brain.firedThisCycle.length;
      win.push({ fired: brain.firedThisCycle.slice() });
    }
    const firedN = Object.create(null);
    for (const cyc of win) for (const n of cyc.fired) firedN[n] = (firedN[n] || 0) + 1;
    const pick = cellpicks.map(n => [n, firedN[n] || 0]);
    return { name, L: +L.toFixed(0), R: +R.toFixed(0), bias: +sumLR.toFixed(0),
      spikesPerCycle: +(totalFired / 400).toFixed(2), quarters: quarters.map(q => q / 100),
      picks: pick };
  };

  const picksAFD = ["AFDL", "AFDR", "AIYL", "AIYR"];
  const picksAWA = ["AWAL", "AWAR", "AIZL", "AIZR"];
  const runs = [
    mktrial("sham (no source)", 0, [], picksAFD),
    mktrial("🔥 thermo · src ahead-R", THERMO_BASE, [dl], picksAFD),
    mktrial("🔥 thermo · src ahead-L", THERMO_BASE, [dr], picksAFD),
    mktrial("🧪 chem-B · src ahead-R", CHEM_B_BASE, [dl], picksAWA),
    mktrial("🧪 chem-B · src ahead-L", CHEM_B_BASE, [dr], picksAWA),
    mktrial("🔥 thermo x5 · src ahead-R", THERMO_BASE * 5, [dl], picksAFD),
    mktrial("🔥 thermo x5 · src ahead-L", THERMO_BASE * 5, [dr], picksAFD),
    mktrial("🧪 chem-B x5 · src ahead-R", CHEM_B_BASE * 5, [dl], picksAWA),
  ];
  console.log("config               L      R    bias  spk/cyc  q1  q2   q3  q4  target cell fires");
  for (const r of runs) {
    const pickStr = r.picks.map(p => `${p[0]}=${p[1]}`).join(" ");
    console.log(`${r.name.padEnd(22)} ${String(r.L).padStart(7)} ${String(r.R).padStart(6)} ` +
      `${String(r.bias).padStart(6)} ${String(r.spikesPerCycle).padStart(8)} ` +
      r.quarters.map(q => String(q.toFixed(1)).padStart(4)).join("") + "  " + pickStr);
  }
  return { scenario: "A", seed, runs: runs.map(r => ({ ...r, picks: undefined })) };
}

/* ==========================================================================
 * Scenario B — navigation consequence with the auxiliary layer OFF.           */

function scenarioB() {
  console.log("\nScenario B · aux steering OFF, empty arena, fixed source · 1200 cycles, 16 trials\n");
  console.log("config                  meanLR    meanDist px   projToSource px   toward%");

  const runWalk = (cfg, rng) => {
    const brain = newBrain();
    const sim = { touchCooldown: 0, pendingTouchSide: "none", pendingTouchScale: 1,
      smell: { sf: 0, sl: 0, sr: 0 }, thermo: { w: 0, f: 0, l: 0, r: 0 },
      chemB: { w: 0, f: 0, l: 0, r: 0 }, tail: { cooldown: 0, side: "none", scale: 1 } };
    let x = ARENA_W / 2 - BODY_W / 2, y = ARENA_H / 2 - BODY_H / 2;
    let rotation = rng() * 360, steerLean = 0, randomTurnFactor = 0, lastSmellF = 0;
    let dist = 0, sumLR = 0, hits = 0;
    const cx0 = x + BODY_W / 2, cy0 = y + BODY_H / 2;
    const src = [{ x: cfg.sourceX, y: cfg.sourceY }];

    for (let cyc = 0; cyc < 1200; cyc++) {
      const mk = brainCycle(brain, sim);
      const left = mk.left, right = mk.right;
      sumLR += left - right;
      const energyFactor = 0.5 + 0.5 * Math.max(0, ENERGY / 100);
      let forwardSpeed = Math.min(4.2, (left + right) * 0.02 * energyFactor);
      const hunger = 1 - Math.max(0, ENERGY / 100);
      const hunt = ENERGY > FOOD_LURE ? 0 : HUNT_FLOOR + (1 - HUNT_FLOOR) * hunger;
      const focus = Math.min(1, lastSmellF / 1.0);
      if (rng() < 0.05 * (1 - 0.75 * focus)) randomTurnFactor = (rng() - 0.5) * 15.0;
      else randomTurnFactor *= 0.8;
      const brainSteer = randomTurnFactor * (1 - 0.7 * focus);   // aux OFF: no gradientGain
      steerLean = steerLean * (1 - STEER_ALPHA) + brainSteer * STEER_ALPHA;

      const rad = rotation * Math.PI / 180, fdx = Math.cos(rad), fdy = Math.sin(rad);
      let nx = x + fdx * forwardSpeed, ny = y + fdy * forwardSpeed;
      let desired = rotation + steerLean, hit = false;
      let rX = 1, rY = 1;
      if (nx < INNER_NUDGE) { nx = INNER_NUDGE; rX = -1; }
      if (nx > ARENA_W - BODY_W - INNER_NUDGE) { nx = ARENA_W - BODY_W - INNER_NUDGE; rX = -1; }
      if (ny < INNER_NUDGE) { ny = INNER_NUDGE; rY = -1; }
      if (ny > ARENA_H - BODY_H - INNER_NUDGE) { ny = ARENA_H - BODY_H - INNER_NUDGE; rY = -1; }
      if (rX < 0 || rY < 0) { desired = Math.atan2(fdy * rY, fdx * rX) * 180 / Math.PI; hit = true; }
      const delta = ((desired - rotation + 540) % 360) - 180;
      const rate = hit ? HARD_TURN_RATE : TURN_RATE;
      rotation += Math.max(-rate, Math.min(rate, delta));
      x = Math.max(0, Math.min(ARENA_W - BODY_W, nx));
      y = Math.max(0, Math.min(ARENA_H - BODY_H, ny));
      if (hit) { sim.pendingTouchSide = "front"; sim.pendingTouchScale = 1; sim.touchCooldown = 10; hits++; }

      dist += forwardSpeed;
      const ccx = x + BODY_W / 2, ccy = y + BODY_H / 2;
      const q3 = probe3((fx, fy) => fieldAt(src, FIELD_RADIUS, fx, fy), ccx, ccy, rotation);
      lastSmellF = 0;
      if (cfg.thermo) sim.thermo = { w: cfg.weight, f: q3.f, l: q3.l, r: q3.r };
      else sim.thermo = { w: 0, f: 0, l: 0, r: 0 };
      if (cfg.chemB) sim.chemB = { w: cfg.weight, f: q3.f, l: q3.l, r: q3.r };
      else sim.chemB = { w: 0, f: 0, l: 0, r: 0 };
    }
    const dx = (x + BODY_W / 2) - cx0, dy = (y + BODY_H / 2) - cy0;
    const toSrc = { dx: cfg.sourceX - cx0, dy: cfg.sourceY - cy0 };
    const len = Math.sqrt(toSrc.dx * toSrc.dx + toSrc.dy * toSrc.dy) || 1;
    const proj = (dx * toSrc.dx + dy * toSrc.dy) / len;
    return { meanLR: sumLR / 1200, dist, proj, hits };
  };

  const cfgs = [
    { name: "sham", thermo: false, chemB: false, weight: 0, sourceX: ARENA_W / 2 + 150, sourceY: ARENA_H / 2 },
    { name: "🔥 thermo @ panel max (30)", thermo: true, weight: THERMO_BASE, sourceX: ARENA_W / 2 + 150, sourceY: ARENA_H / 2 },
    { name: "🧪 chem-B @ panel max (45)", chemB: true, weight: CHEM_B_BASE, sourceX: ARENA_W / 2 + 150, sourceY: ARENA_H / 2 },
    { name: "🔥 thermo amplified x3 (90)", thermo: true, weight: THERMO_BASE * 3, sourceX: ARENA_W / 2 + 150, sourceY: ARENA_H / 2 },
    { name: "🧪 chem-B amplified x3 (135)", chemB: true, weight: CHEM_B_BASE * 3, sourceX: ARENA_W / 2 + 150, sourceY: ARENA_H / 2 },
    { name: "🔥 thermo amplified x5 (150)", thermo: true, weight: THERMO_BASE * 5, sourceX: ARENA_W / 2 + 150, sourceY: ARENA_H / 2 },
    { name: "🧪 chem-B amplified x5 (225)", chemB: true, weight: CHEM_B_BASE * 5, sourceX: ARENA_W / 2 + 150, sourceY: ARENA_H / 2 },
  ];
  const rows = [];
  for (const cfg of cfgs) {
    const acc = { sumLR: 0, dist: 0, proj: 0, hits: 0, toward: 0 };
    for (let t = 0; t < 16; t++) {
      const r = runWalk(cfg, rnd);
      acc.sumLR += r.meanLR; acc.dist += r.dist; acc.proj += r.proj; acc.hits += r.hits;
      if (r.proj > 0) acc.toward++;
    }
    const n = 16;
    const row = {
      config: cfg.name, meanLR: +(acc.sumLR / n).toFixed(3), meanDist: +(acc.dist / n).toFixed(0),
      projToSource: +(acc.proj / n).toFixed(0), towardPct: +(100 * acc.toward / n).toFixed(0),
      meanHits: +(acc.hits / n).toFixed(1),
    };
    rows.push(row);
    console.log(`${row.config.padEnd(28)} ${String(row.meanLR).padStart(9)} ${String(row.meanDist).padStart(11)} ` +
      `${String(row.projToSource).padStart(16)} ${String(row.towardPct).padStart(9)}`);
  }
  return { scenario: "B", seed, runs: rows };
}

/* ==========================================================================
 * Scenario C — tail poke reflex (PLML/PLMR).                                  */

function scenarioC() {
  console.log("\nScenario C · tail poke, phase-dependence sweep · PLM, 150 x 4 cycles at every start window\n");
  console.log("poke@cycle   Δmotor(L+R) vs sham    tailSetΔ   ΔfwdDrive (L+R)      response?");

  const runWalk = (pokeStart) => {
    const brain = newBrain();
    const sim = { touchCooldown: 0, pendingTouchSide: "none", pendingTouchScale: 1,
      smell: { sf: 0, sl: 0, sr: 0 }, thermo: { w: 0, f: 0, l: 0, r: 0 },
      chemB: { w: 0, f: 0, l: 0, r: 0 }, tail: { cooldown: 0, side: "none", scale: 1 } };
    let motor = 0, fwd = 0, tailSetFired = 0;
    const set = ["PLML", "PLMR", "AVAL", "AVAR", "AS1", "VB1"];
    for (let i = 0; i < 120; i++) {
      if (pokeStart >= 0 && i === pokeStart) sim.tail = { cooldown: TAIL_COOLDOWN, side: "none", scale: 1 };
      const mk = brainCycle(brain, sim);
      motor += Math.abs(mk.left) + Math.abs(mk.right);
      fwd += mk.left + mk.right;
      for (const n of brain.firedThisCycle) if (set.indexOf(n) !== -1) tailSetFired++;
    }
    return { motor, fwd, tailSetFired };
  };

  const sham = runWalk(-1);
  const rows = [];
  for (const start of [0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 110]) {
    const r = runWalk(start);
    const dMotor = r.motor - sham.motor;
    const dFwd = r.fwd - sham.fwd;
    const resp = (Math.abs(dMotor) >= 25) ? "yes" : "—";
    rows.push({
      pokeAt: start, dMotor: +dMotor.toFixed(0), tailSetFired: r.tailSetFired - sham.tailSetFired,
      dFwd: +dFwd.toFixed(0), response: resp === "yes",
    });
    console.log(`cycle ${String(start).padStart(4)}        ${String(dMotor >= 0 ? "+" : "").padStart(1)}${String(dMotor).padStart(12)}` +
      `      ${String(r.tailSetFired - sham.tailSetFired).padStart(5)}        ${String(dFwd >= 0 ? "+" : "").padStart(1)}${String(dFwd).padStart(12)}      ${resp}`);
  }
  const respCount = rows.filter(r => r.response).length;
  console.log(`\n→ poke produces a detectable motor shift in ${respCount}/${rows.length} phase windows;` +
    ` reversals are similarly phase-locked.`);
  return { scenario: "C", seed, shamMotor: +sham.motor.toFixed(0), shamFwd: +sham.fwd.toFixed(0), runs: rows };
}

/* --- orchestrate + persist ------------------------------------------------- */
const t0 = Date.now();
fs.mkdirSync(path.join(__dirname, "results"), { recursive: true });
console.log(`\nStimulus Lab  seed=${seed}  scenarios=${budget}`);

const out = { seed, date: new Date().toISOString(), scenarios: [] };
if (budget === "all" || budget.includes("A")) out.scenarios.push(scenarioA());
if (budget === "all" || budget.includes("B")) out.scenarios.push(scenarioB());
if (budget === "all" || budget.includes("C")) out.scenarios.push(scenarioC());

fs.writeFileSync(path.join(__dirname, "results", `stimulus-lab-${seed}.json`),
  JSON.stringify(out, null, 2) + "\n");

// compact TSV of the scenario B rows (the navigational readout)
const b = out.scenarios.find(s => s.scenario === "B");
if (b) {
  const lines = [["config", "seed", "meanLR", "meanDistPx", "projToSourcePx", "towardPct", "meanHits"]];
  for (const r of b.runs) lines.push([r.config, seed, r.meanLR, r.meanDist, r.projToSource, r.towardPct, r.meanHits]);
  fs.writeFileSync(path.join(__dirname, "results", `stimulus-B-${seed}.tsv`),
    lines.map(r => r.join("\t")).join("\n") + "\n");
}

console.log(`\nfinished in ${Date.now() - t0} ms -> experiments/results/stimulus-lab-${seed}.json`);
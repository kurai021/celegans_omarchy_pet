/* Circuit Tuner (Phase A): do synapse patches change what the real connectome
 * does? From the Phase C reading we know the worm is very dissipative and that
 * amplifying injected current 10-20x collapses homing. Phase A edits the wiring
 * directly — so the honest question is different:
 *
 *   does rewiring some synapses (presets from the Circuit Lab overlay, applied
 *   with the SAME engine: Celegans.js setCircuitPatches) move:
 *     A. food-searching success in the aux-off config (the one where the pet
 *        only has its own steering), and
 *     B. the tail-touch reflex burst vs. a sham poke?
 *
 * Everything below is transcribed 1:1 from honesty-check.js (walk) and
 * stimulus-lab.js (tail poke) so the numbers are comparable. The ONLY new
 * ingredient is the patch map applied to the REAL brain before/without any
 * Panel code running. Seeds make every run reproducible.
 */

const fs = require("fs");
const vm = require("vm");
const path = require("path");

const DIR = path.join(__dirname, "..", "panels");

/* --- seeded RNG (same as the Phase B/C harnesses) ------------------------- */
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
let trials = 40;
let budget = "all"; // "all" | "A" | "B"
for (let i = 2; i < process.argv.length; i++) {
  const m = /^--seed=(\d+)$/.exec(process.argv[i]);
  if (m) seed = Math.abs(parseInt(m[1], 10)) || seed;
  const t = /^--trials=(\d+)$/.exec(process.argv[i]);
  if (t) trials = Math.max(4, Math.min(200, parseInt(t[1], 10) || 40));
  const s = /^--scenario=([AB,]+)$/.exec(process.argv[i]);
  if (s) budget = s[1].toUpperCase();
}
const rnd = mulberry32(seed);

const ctx = { Math, Date, console };
ctx.Math.random = rnd;
vm.createContext(ctx);
vm.runInContext(fs.readFileSync(path.join(DIR, "Celegans.js"), "utf8"), ctx);
const Brain = ctx.Brain;

/* --- constants transcribed from the UI/runtime (same as Phase B/C) --------- */
const ARENA_W = 640, ARENA_H = 480;
const BODY_RADIUS = 17, TURN_RATE = 28, HARD_TURN_RATE = 60;
const INNER_NUDGE = 2, EAT_REACH = 26;
const BODY_W = 60, BODY_H = 90;
const FORWARD_PROBE = 80, SIDE_FORWARD = 60, SIDE_SPREAD = 24;
const SMELL_RADIUS = 220;
const ENERGY = 50;
const STEER_ALPHA = 0.35;
const FOOD_LURE = 90, HUNT_FLOOR = 0.3;
const TAIL_CHARGE = 150, TAIL_COOLDOWN = 4;

const PELLET_SPOTS = [
  { x: 520, y: 360 },
  { x: 100, y: 360 },
  { x: 520, y: 110 },
  { x: 100, y: 110 },
];

/* --- self-check: the introspected base weights must match the real ones ---- */
function selfCheckBrain() {
  const brain = new Brain();
  brain.setup();
  const checks = [
    ["AFDL", "AIYL", 7], ["ADFL", "AIZL", 12], ["ADFR", "AIZR", 8],
    ["AIZL", "SMBDL", 9], ["AIZR", "SMBDR", 5], ["AIZL", "SMBVL", 7],
    ["AVL", "MVL10", -5], ["AVAL", "DA6", 21], ["ALML", "BDUL", 6],
    ["PLMR", "AVDL", 1],
    ["PLML", "AVDR", 0],  // really absent -> escape preset creates a new route
    ["ADFL", "SMDVL", 0], // really absent -> shortcut preset adds new wiring
  ];
  let ok = true;
  for (const [from, to, want] of checks) {
    const got = brain.synapseBaseOf(from, to);
    const pass = got === want;
    if (!pass) ok = false;
    console.log(`  base ${from}→${to}: got ${got} want ${want} ${pass ? "✓" : "✗ MISMATCH"}`);
  }
  const prev = brain.synapseList().length;
  console.log(`  total real synapses introspected: ${prev}`);
  return ok;
}

/* --- patch maps: identical lists to the Circuit Lab presets ----------------- */
const PRESETS = {
  "control": null,
  "chemotaxis": [
    ["ADFL", "AIZL", 18], ["ADFR", "AIZR", 12], ["AIZL", "SMBDL", 14],
    ["AIZR", "SMBDR", 9], ["AIZL", "SMBVL", 10], ["AIZR", "SMBVR", 5],
  ],
  "escape": [
    ["PLML", "AVDR", 5], ["PLMR", "AVDL", 5], ["AVDR", "AVAL", 24], ["AVDL", "AVAR", 28],
  ],
  "shortcut": [
    ["ADFL", "SMDVL", 4], ["ADFR", "SMDVR", 4], ["AFDL", "SMBVL", 5], ["AFDR", "SMBVR", 5],
  ],
  "calm": [
    ["ALML", "BDUL", 3], ["ALMR", "BDUR", 3], ["ALML", "AVDR", 0], ["PLMR", "AVDR", 0],
  ],
  "all": null, // union below
};
const union = [];
for (const k of ["chemotaxis", "escape", "shortcut", "calm"])
  for (const p of PRESETS[k]) union.push(p);
PRESETS.all = union;

function applyPatches(brain, patches) {
  if (!patches || !patches.length) return;
  const map = {};
  for (const [from, to, w] of patches) map[`${from}:${to}`] = w;
  brain.setCircuitPatches(map);
}

/* --- world smell (World.qml, identical falloff) ---------------------------- */
function smellAt(food, x, y) {
  const dx = food.x - x, dy = food.y - y;
  const d = Math.sqrt(dx * dx + dy * dy);
  if (d < SMELL_RADIUS) { const t = 1 - d / SMELL_RADIUS; return t * t; }
  return 0;
}

/* --- one cycle, faithful BrainConnector order ------------------------------ */
function brainCycle(brain, cfg, sim) {
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

  const { sf, sl, sr } = sim.smell;
  if (sl > 0 || sr > 0 || sf > 0) {
    const bal = sl - sr;
    if (Math.abs(bal) > 0.02) {
      brain.postSynaptic["ADFL"][next] += cfg.chemoSideWeight * bal;
      brain.postSynaptic["ADFR"][next] += -cfg.chemoSideWeight * bal;
    }
    const drive = cfg.chemoSideWeight * 0.4 * sf;
    if (drive > 0) { brain.postSynaptic["ADFL"][next] += drive; brain.postSynaptic["ADFR"][next] += drive; }
  }
  sim.smell.sf = sim.smell.sl = sim.smell.sr = 0;

  brain.update();
  const left = brain.accumleft, right = brain.accumright;
  brain.accumleft = 0; brain.accumright = 0;
  return { left, right };
}

/* ==========================================================================
 * Scenario A — navigation, aux steering OFF (only the connectome steers).   */

function scenarioA() {
  console.log(`\nScenario A · patches vs food-searching (aux OFF: only the wiring steers) · ${trials} trials/run\n`);
  console.log("config                 success%  medCyc  meanCyc  dist px  spk/cyc  meanLR");

  const runTrial = (patches, pellet, rng) => {
    const brain = new Brain();
    brain.setup();
    brain.stimulateFoodSenseNeurons = true;
    applyPatches(brain, patches);

    const sim = { touchCooldown: 0, pendingTouchSide: "none", pendingTouchScale: 1,
      smell: { sf: 0, sl: 0, sr: 0 } };
    let x = ARENA_W / 2 - BODY_W / 2, y = ARENA_H / 2 - BODY_H / 2;
    let rotation = rng() * 360, steerLean = 0, randomTurnFactor = 0, lastSmellForward = 0;
    let distance = 0, spikes = 0, sumLR = 0, cycles = 0, foundAt = -1;
    const MAX_CYCLES = 2000;

    for (let cyc = 0; cyc < MAX_CYCLES; cyc++) {
      cycles = cyc + 1;
      const mk = brainCycle(brain, cfgOff, sim);
      const left = mk.left, right = mk.right;
      spikes += brain.firedThisCycle.length;
      sumLR += left - right;

      const energyFactor = 0.5 + 0.5 * Math.max(0, ENERGY / 100);
      let forwardSpeed = (left + right) * 0.02 * energyFactor;
      forwardSpeed = Math.min(4.2, forwardSpeed);
      const hunger = 1 - Math.max(0, ENERGY / 100);
      const hunt = ENERGY > FOOD_LURE ? 0 : HUNT_FLOOR + (1 - HUNT_FLOOR) * hunger;
      const focus = Math.min(1, lastSmellForward / 1.0);
      if (rng() < 0.05 * (1 - 0.75 * focus)) randomTurnFactor = (rng() - 0.5) * 15.0;
      else randomTurnFactor *= 0.8;
      const brainSteer = (left - right) * cfgOff.brainTurnGain
        + randomTurnFactor * (1 - 0.7 * focus);
      steerLean = steerLean * (1 - STEER_ALPHA) + brainSteer * STEER_ALPHA;

      const rad = rotation * Math.PI / 180, fdx = Math.cos(rad), fdy = Math.sin(rad);
      let nx = x + fdx * forwardSpeed, ny = y + fdy * forwardSpeed;
      let desired = rotation + steerLean, hit = false, rX = 1, rY = 1;
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
      if (hit) { sim.pendingTouchSide = "front"; sim.pendingTouchScale = 1; sim.touchCooldown = 10; }

      distance += forwardSpeed;
      const cx = x + BODY_W / 2, cy = y + BODY_H / 2;
      const rad2 = rotation * Math.PI / 180, co = Math.cos(rad2), si = Math.sin(rad2);
      const pfx = cx + co * FORWARD_PROBE, pfy = cy + si * FORWARD_PROBE;
      const sx = cx + co * SIDE_FORWARD, sy = cy + si * SIDE_FORWARD;
      lastSmellForward = smellAt(pellet, pfx, pfy);
      sim.smell.sf = lastSmellForward;
      sim.smell.sl = smellAt(pellet, sx - si * SIDE_SPREAD, sy + co * SIDE_SPREAD);
      sim.smell.sr = smellAt(pellet, sx + si * SIDE_SPREAD, sy - co * SIDE_SPREAD);
      const eatDx = pellet.x - cx, eatDy = pellet.y - cy;
      if (Math.sqrt(eatDx * eatDx + eatDy * eatDy) <= EAT_REACH + 7) { foundAt = cycles; break; }
    }
    return { success: foundAt >= 0, cycles, cyclesToFood: foundAt, distance,
      spikesPerCycle: cycles ? spikes / cycles : 0, meanLR: cycles ? sumLR / cycles : 0 };
  };

  const rows = [];
  for (const name of Object.keys(PRESETS)) {
    const acc = { ok: 0, cyc: 0, allCyc: 0, dist: 0, spk: 0, lr: 0, foundCyc: [] };
    for (let t = 0; t < trials; t++) {
      const pellet = PELLET_SPOTS[t % PELLET_SPOTS.length];
      const r = runTrial(PRESETS[name], pellet, rnd);
      if (r.success) { acc.ok++; acc.cyc += r.cyclesToFood; }
      acc.allCyc += r.cycles; acc.dist += r.distance; acc.spk += r.spikesPerCycle; acc.lr += r.meanLR;
    }
    const n = trials;
    const med = (arr) => {
      if (!arr.length) return "-";
      const s = [...arr].sort((a, b) => a - b);
      const m = Math.floor(s.length / 2);
      return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
    };
    const row = {
      config: name,
      successRate: +(100 * acc.ok / n).toFixed(1),
      medianCyclesToFood: med(acc.foundCyc),
      meanCyclesAll: +(acc.allCyc / n).toFixed(0),
      meanDistPx: +(acc.dist / n).toFixed(0),
      spikesPerCycle: +(acc.spk / n).toFixed(3),
      meanLR: +(acc.lr / n).toFixed(2),
    };
    rows.push(row);
    console.log(`${row.config.padEnd(22)} ${String(row.successRate).padStart(6)}% ${String(row.medianCyclesToFood).padStart(8)} ${
      String(row.meanCyclesAll).padStart(9)} ${String(row.meanDistPx).padStart(10)} ${String(row.spikesPerCycle).padStart(9)} ${
      String(row.meanLR).padStart(8)}`);
  }
  return { scenario: "A", seed, trials, runs: rows };
}

/* ==========================================================================
 * Scenario B — tail-touch reflex, patched vs. control (sham poke baseline).  */

function scenarioB() {
  console.log("\nScenario B · tail poke burst, patched vs control · 120 cycles per phase window\n");
  console.log("config            dMotor(0) dMotor(50)  dFwd(50)   reflex@0/50/110");

  // Tail injection is applied inside the cycle like BrainConnector: a small
  // helper injects the PLM charges (transcribed from BrainConnector's tail
  // block) and hands off to the shared brainCycle.
  const brainCyclePoke = (brain, sim) => {
    const next = brain.nextState;
    if (sim.tail && sim.tail.cooldown > 0) {
      let wl = 1.0, wr = 1.0;
      if (sim.tail.side === "left") { wl = 1.0; wr = 0.5; }
      else if (sim.tail.side === "right") { wl = 0.5; wr = 1.0; }
      const ch = TAIL_CHARGE * sim.tail.scale;
      brain.postSynaptic["PLML"][next] += ch * wl;
      brain.postSynaptic["PLMR"][next] += ch * wr;
      sim.tail.cooldown--;
    }
    sim.tail.side = "none"; sim.tail.scale = 1;
    return brainCycle(brain, cfgOff, sim);
  };
  const runPoke = (patches, pokeStart) => {
    const brain = new Brain();
    brain.setup();
    brain.stimulateFoodSenseNeurons = true;
    applyPatches(brain, patches);
    const sim = { touchCooldown: 0, pendingTouchSide: "none", pendingTouchScale: 1,
      smell: { sf: 0, sl: 0, sr: 0 }, tail: { cooldown: 0, side: "none", scale: 1 } };
    let motor = 0, fwd = 0, tailSetFired = 0;
    const set = ["PLML", "PLMR", "AVAL", "AVAR", "AS1", "VB1"];
    for (let i = 0; i < 120; i++) {
      if (pokeStart >= 0 && i === pokeStart)
        sim.tail = { cooldown: TAIL_COOLDOWN, side: "none", scale: 1 };
      const mk = brainCyclePoke(brain, sim);
      motor += Math.abs(mk.left) + Math.abs(mk.right);
      fwd += mk.left + mk.right;
      for (const n of brain.firedThisCycle) if (set.indexOf(n) !== -1) tailSetFired++;
    }
    return { motor, fwd, tailSetFired };
  };

  const rows = [];
  for (const name of Object.keys(PRESETS)) {
    const sham = runPoke(PRESETS[name], -1);
    const at = (start) => {
      const r = runPoke(PRESETS[name], start);
      return { dMotor: r.motor - sham.motor, dFwd: r.fwd - sham.fwd, tail: r.tailSetFired - sham.tailSetFired };
    };
    const p0 = at(0), p50 = at(50), p110 = at(110);
    const reflexes = [p0, p50, p110].map(p => (Math.abs(p.dMotor) >= 25 ? "yes" : "—")).join("/");
    rows.push({ config: name, dMotor0: +p0.dMotor.toFixed(0), dMotor50: +p50.dMotor.toFixed(0),
      dFwd50: +p50.dFwd.toFixed(0), reflex: reflexes });
    console.log(`${name.padEnd(18)} ${String(p0.dMotor >= 0 ? "+" : "").padStart(1)}${String(p0.dMotor).padStart(10)} ${
      String(p50.dMotor >= 0 ? "+" : "").padStart(1)}${String(p50.dMotor).padStart(9)} ${
      String(p50.dFwd >= 0 ? "+" : "").padStart(1)}${String(p50.dFwd).padStart(9)}     ${reflexes}`);
  }
  return { scenario: "B", seed, runs: rows };
}

/* --- orchestrate + persist ------------------------------------------------- */
const cfgOff = { chemoSideWeight: 26, brainTurnGain: 0, gradientGain: 0, maxGradientTurn: 60 };

const t0 = Date.now();
fs.mkdirSync(path.join(__dirname, "results"), { recursive: true });
console.log(`\nCircuit Tuner  seed=${seed}  trials=${trials}  scenarios=${budget}`);

console.log("\n· base-weight self-check (the introspector must see the real wiring)");
const sane = selfCheckBrain();
if (!sane) { console.log("\nABORT: synapse introspection mismatch — do not trust these results."); process.exit(1); }

const out = { seed, date: new Date().toISOString(), scenarios: [] };
if (budget === "all" || budget.includes("A")) out.scenarios.push(scenarioA());
if (budget === "all" || budget.includes("B")) out.scenarios.push(scenarioB());

fs.writeFileSync(path.join(__dirname, "results", `circuit-tuner-${seed}.json`),
  JSON.stringify(out, null, 2) + "\n");

const a = out.scenarios.find(s => s.scenario === "A");
if (a) {
  const lines = [["config", "seed", "trials", "success%", "medCyclesToFood", "meanCyclesAll", "meanDistPx", "spikesPerCycle", "meanLR"]];
  for (const r of a.runs) lines.push([r.config, seed, trials, r.successRate, r.medianCyclesToFood, r.meanCyclesAll, r.meanDistPx, r.spikesPerCycle, r.meanLR]);
  fs.writeFileSync(path.join(__dirname, "results", `circuit-A-${seed}.tsv`),
    lines.map(r => r.join("\t")).join("\n") + "\n");
}

console.log(`\nfinished in ${Date.now() - t0} ms -> experiments/results/circuit-tuner-${seed}.json`);
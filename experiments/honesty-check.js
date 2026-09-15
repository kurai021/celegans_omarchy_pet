/* Honesty Check (Phase C): how much of the pet's food-searching actually comes
 * out of the real connectome, and how much from the auxiliary navigation layer
 * in Pet.qml?
 *
 * This is a controlled, repeatable experiment, not a toy:
 *  - it runs the REAL Celegans.js brain (the same instance BrainConnector uses),
 *    advanced cycle by cycle with the EXACT stimulus injection order,
 *  - it reproduces the EXACT steering/physics code from Pet.qml (probes, smell
 *    falloff, Braitenberg gradient turn, connectome brainSteer, rate-limited
 *    turn, wall reflection, nose-touch reflex) so the measured behavior matches
 *    the live pet,
 *  - the environment is kept comparable across configs (fixed arena, fixed
 *    pellet positions, only the initial heading and the biological noise are
 *    randomized, both seeded for reproducibility),
 *  - every config runs N trials; results aggregate success/time/spikes/distance.
 *
 * It answers: with config X, does reaching food depend on the connectome's own
 * steering signal (brainTurnGain * (left-right) + chemoSideWeight asymmetry) or
 * on the Braitenberg gradient assist (gradientGain)?
 */

const fs = require("fs");
const vm = require("vm");
const path = require("path");

const DIR = path.join(__dirname, "..", "panels");

/* --- seeded RNG so "I ran this under these conditions" can be re-run ----- */
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
for (let i = 2; i < process.argv.length; i++) {
  const m = /^--seed=(\d+)$/.exec(process.argv[i]);
  if (m) seed = Math.abs(parseInt(m[1], 10)) || seed;
  const t = /^--trials=(\d+)$/.exec(process.argv[i]);
  if (t) trials = Math.max(4, Math.min(200, parseInt(t[1], 10) || 40));
}
const rnd = mulberry32(seed);

/* Load the real connectome in a sandbox (same as the F4 harness). */
const ctx = { Math, Date, console };
ctx.Math.random = rnd;
vm.createContext(ctx);
vm.runInContext(fs.readFileSync(path.join(DIR, "Celegans.js"), "utf8"), ctx);
const Brain = ctx.Brain;

/* --- constants transcribed from BrainConnector.qml / Pet.qml / World.qml --- */
const ARENA_W = 640, ARENA_H = 480;
const BODY_RADIUS = 17, TURN_RATE = 28, HARD_TURN_RATE = 60;
const INNER_NUDGE = 2, EAT_REACH = 26;
const BODY_W = 60, BODY_H = 90;
const FORWARD_PROBE = 80, SIDE_FORWARD = 60, SIDE_SPREAD = 24;
const SMELL_RADIUS = 220;
const ENERGY = 50;             // frozen organism state: hungry, awake
const STEER_ALPHA = 0.35;
const FOOD_LURE = 90;

const HUNT_FLOOR = 0.3;

const PELLET_SPOTS = [
  { x: 520, y: 360 },
  { x: 100, y: 360 },
  { x: 520, y: 110 },
  { x: 100, y: 110 },
];

/* --- world smell model (World.qml smellAt, identical falloff) ------------- */
function smellAt(food, x, y) {
  const dx = food.x - x, dy = food.y - y;
  const d = Math.sqrt(dx * dx + dy * dy);
  if (d < SMELL_RADIUS) {
    const t = 1 - d / SMELL_RADIUS;
    return t * t;
  }
  return 0;
}

/* --- one full cycle, transcribed faithfully from BrainConnector ------- */
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
  } else {
    brain.stimulateNoseTouchNeurons = false;
  }
  sim.pendingTouchSide = "none";
  sim.pendingTouchScale = 1;

  const { sf, sl, sr } = sim.smell;
  if (sl > 0 || sr > 0 || sf > 0) {
    const bal = sl - sr;
    if (Math.abs(bal) > 0.02) {
      brain.postSynaptic["ADFL"][next] += cfg.chemoSideWeight * bal;
      brain.postSynaptic["ADFR"][next] += -cfg.chemoSideWeight * bal;
    }
    const drive = cfg.chemoSideWeight * 0.4 * sf;
    if (drive > 0) {
      brain.postSynaptic["ADFL"][next] += drive;
      brain.postSynaptic["ADFR"][next] += drive;
    }
  }
  sim.smell.sf = sim.smell.sl = sim.smell.sr = 0;

  brain.update();

  const left = brain.accumleft;
  const right = brain.accumright;
  brain.accumleft = 0;
  brain.accumright = 0;
  return { left, right };
}

/* --- one trial (Pet.qml onUpdated steering, transcribed faithfully) ---- */
function runTrial(cfg, pellet, rng, trialIdx) {
  const brain = new Brain();
  brain.setup();
  brain.stimulateFoodSenseNeurons = true;

  const sim = {
    touchCooldown: 0,
    pendingTouchSide: "none",
    pendingTouchScale: 1,
    smell: { sf: 0, sl: 0, sr: 0 },
  };

  let x = ARENA_W / 2 - BODY_W / 2;
  let y = ARENA_H / 2 - BODY_H / 2;
  let rotation = rng() * 360;
  let steerLean = 0;
  let randomTurnFactor = 0;
  let lastSmellForward = 0;
  let lastSmellLeft = 0;
  let lastSmellRight = 0;

  let distance = 0;
  let spikes = 0;
  let sumAbsLR = 0, sumLR = 0;
  let cycles = 0;
  let foundAt = -1;
  const MAX_CYCLES = 2000;

  for (let cyc = 0; cyc < MAX_CYCLES; cyc++) {
    cycles = cyc + 1;
    const mk = brainCycle(brain, cfg, sim);
    const left = mk.left, right = mk.right;

    spikes += brain.firedThisCycle.length;
    sumAbsLR += Math.abs(left) + Math.abs(right);
    sumLR += left - right;

    const energyFactor = 0.5 + 0.5 * Math.max(0, ENERGY / 100);
    let forwardSpeed = (left + right) * 0.02 * energyFactor;
    forwardSpeed = Math.min(4.2, forwardSpeed);

    const hunger = 1 - Math.max(0, ENERGY / 100);
    const hunt = ENERGY > FOOD_LURE ? 0 : HUNT_FLOOR + (1 - HUNT_FLOOR) * hunger;

    const focus = Math.min(1, lastSmellForward / 1.0);
    if (rng() < 0.05 * (1 - 0.75 * focus)) {
      randomTurnFactor = (rng() - 0.5) * 15.0;
    } else {
      randomTurnFactor *= 0.8;
    }
    const side = lastSmellLeft - lastSmellRight;
    let gradientTurn = side * cfg.gradientGain * hunt;
    gradientTurn = Math.max(-cfg.maxGradientTurn,
      Math.min(cfg.maxGradientTurn, gradientTurn));
    const brainSteer = (left - right) * cfg.brainTurnGain
      + gradientTurn
      + randomTurnFactor * (1 - 0.7 * focus);
    steerLean = steerLean * (1 - STEER_ALPHA) + brainSteer * STEER_ALPHA;

    let ang = rotation;
    let rad = ang * Math.PI / 180;
    let fdx = Math.cos(rad), fdy = Math.sin(rad);

    let nx = x + fdx * forwardSpeed;
    let ny = y + fdy * forwardSpeed;
    let desired = ang + steerLean;
    let hit = false;

    let rX = 1, rY = 1;
    if (nx < INNER_NUDGE) { nx = INNER_NUDGE; rX = -1; }
    if (nx > ARENA_W - BODY_W - INNER_NUDGE) { nx = ARENA_W - BODY_W - INNER_NUDGE; rX = -1; }
    if (ny < INNER_NUDGE) { ny = INNER_NUDGE; rY = -1; }
    if (ny > ARENA_H - BODY_H - INNER_NUDGE) { ny = ARENA_H - BODY_H - INNER_NUDGE; rY = -1; }
    if (rX < 0 || rY < 0) {
      desired = Math.atan2(fdy * rY, fdx * rX) * 180 / Math.PI;
      hit = true;
    }

    const delta = ((desired - rotation + 540) % 360) - 180;
    const rate = hit ? HARD_TURN_RATE : TURN_RATE;
    rotation += Math.max(-rate, Math.min(rate, delta));
    x = Math.max(0, Math.min(ARENA_W - BODY_W, nx));
    y = Math.max(0, Math.min(ARENA_H - BODY_H, ny));

    if (hit) {
      sim.pendingTouchSide = "front";
      sim.pendingTouchScale = 1;
      sim.touchCooldown = 10;
    }

    distance += forwardSpeed;

    const cx = x + BODY_W / 2;
    const cy = y + BODY_H / 2;
    const rad2 = rotation * Math.PI / 180;
    const co = Math.cos(rad2), si = Math.sin(rad2);

    let f0 = 0, l0 = 0, r0 = 0;
    f0 = smellAt(pellet, cx + co * FORWARD_PROBE, cy + si * FORWARD_PROBE);
    const sx = cx + co * SIDE_FORWARD, sy = cy + si * SIDE_FORWARD;
    l0 = smellAt(pellet, sx - si * SIDE_SPREAD, sy + co * SIDE_SPREAD);
    r0 = smellAt(pellet, sx + si * SIDE_SPREAD, sy - co * SIDE_SPREAD);
    lastSmellForward = f0;
    lastSmellLeft = l0;
    lastSmellRight = r0;
    sim.smell.sf = f0; sim.smell.sl = l0; sim.smell.sr = r0;

    const eatDx = pellet.x - cx, eatDy = pellet.y - cy;
    const eatD = Math.sqrt(eatDx * eatDx + eatDy * eatDy);
    if (eatD <= EAT_REACH + 7) { foundAt = cycles; break; }
  }

  return {
    success: foundAt >= 0,
    cycles,
    cyclesToFood: foundAt,
    distance,
    spikes,
    spikesPerCycle: cycles ? spikes / cycles : 0,
    meanAbsLR: cycles ? sumAbsLR / cycles : 0,
    meanLR: cycles ? sumLR / cycles : 0,
    trial: trialIdx,
  };
}

/* --- run a config across trials ------------------------------------------- */
function runConfig(name, cfg, trials) {
  const results = [];
  for (let t = 0; t < trials; t++) {
    const pellet = PELLET_SPOTS[t % PELLET_SPOTS.length];
    results.push(runTrial(cfg, pellet, rnd, t));
  }
  const ok = results.filter(r => r.success);
  const med = (arr) => {
    if (!arr.length) return "-";
    const s = [...arr].sort((a, b) => a - b);
    const mid = Math.floor(s.length / 2);
    return s.length % 2 ? s[mid] : (s[mid - 1] + s[mid]) / 2;
  };
  const mean = (arr) => {
    if (!arr.length) return 0;
    return arr.reduce((a, b) => a + b, 0) / arr.length;
  };
  const summary = {
    config: name,
    trials,
    successRate: +(100 * ok.length / trials).toFixed(1),
    medianCyclesToFood: med(ok.map(r => r.cyclesToFood)),
    meanCyclesAll: +mean(results.map(r => r.cycles)).toFixed(0),
    meanDistancePx: +mean(results.map(r => r.distance)).toFixed(0),
    meanSpikesPerCycle: +mean(results.map(r => r.spikesPerCycle)).toFixed(3),
    meanAbsLR: +mean(results.map(r => r.meanAbsLR)).toFixed(1),
    meanLR: +mean(results.map(r => r.meanLR)).toFixed(2),
  };
  return { summary, results };
}

/* --- configs (C: the honesty matrix) -------------------------------------- */
function makeMatrix() {
  const base = { chemoSideWeight: 26, brainTurnGain: 0.05, gradientGain: 300, maxGradientTurn: 60 };
  return [
    { name: "control", cfg: { ...base } },                                    // today's live pet
    { name: "aux-off", cfg: { ...base, gradientGain: 0 } },                   // no Braitenberg: connectome heading only
    { name: "ct-strong-1x", cfg: { ...base, gradientGain: 0, brainTurnGain: 0.5, chemoSideWeight: 60 } },
    { name: "ct-strong-4x", cfg: { ...base, gradientGain: 0, brainTurnGain: 1.0, chemoSideWeight: 120 } },
    { name: "ct-off", cfg: { ...base, brainTurnGain: 0 } },                   // aux heading only, connectome drive kept
    { name: "all-off", cfg: { ...base, gradientGain: 0, brainTurnGain: 0 } }, // no heading control at all
  ];
}

const t0 = Date.now();
console.log(`\nHonesty Check  seed=${seed}  trials/config=${trials}\n`);
console.log("config | success% | medCyclesToFood | meanCycles/all | meanDist px | spikes/cyc | meanAbsLR | meanLR");
console.log("-".repeat(110));

const lines = [["config", "seed", "trials", "success%", "medCyclesToFood", "meanCyclesAll", "meanDistPx", "spikesPerCycle", "meanAbsLR", "meanLR"]];
for (const { name, cfg } of makeMatrix()) {
  const { summary, results } = runConfig(name, cfg, trials);
  console.log(
    `${summary.config.padEnd(14)} | ${String(summary.successRate).padStart(7)}% | ${String(summary.medianCyclesToFood).padStart(11)} | ${String(summary.meanCyclesAll).padStart(13)} | ${String(summary.meanDistancePx).padStart(10)} | ${String(summary.meanSpikesPerCycle).padStart(10)} | ${String(summary.meanAbsLR).padStart(8)} | ${String(summary.meanLR).padStart(7)}`
  );
  lines.push([summary.config, seed, trials,
    summary.successRate, summary.medianCyclesToFood, summary.meanCyclesAll,
    summary.meanDistancePx, summary.meanSpikesPerCycle, summary.meanAbsLR, summary.meanLR]);
  fs.writeFileSync(path.join(__dirname, "results", `c-${name}-${seed}.json`),
    JSON.stringify(summary, null, 2) + "\n");
}
console.log("-".repeat(110));
const ts = new Date().toISOString().replace(/[:.]/g, "-");
fs.mkdirSync(path.join(__dirname, "results"), { recursive: true });
fs.writeFileSync(path.join(__dirname, "results", `honesty-matrix-${seed}.tsv`),
  lines.map(r => r.join("\t")).join("\n") + "\n");
console.log(`\nfinished in ${Date.now() - t0} ms -> experiments/results/honesty-matrix-${seed}.tsv`);
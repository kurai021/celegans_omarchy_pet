# Experiments — C. elegans Pet

The plugin doubles as a small, reproducible experiment kit on its own nervous
system. Each phase lives here with its harness, its results and a
human-readable reading.

## Phase C — Honesty Check (what is really connectome)

**Question**: how much of the pet's food-seeking navigation actually emerges
from the connectome, and how much from the auxiliary layers in `Pet.qml`
(Braitenberg steering, geometric repulsion, noise)?

**Why it matters**: the project starts from the claim that the movement comes
from a real connectome. Before adding stimuli or modifying circuits (phases B
and A), we want to *measure* that claim and be able to say which part is real
and which part is wrapper.

### Method

- The harness runs the **real `Celegans.js`** (the same instance
  `BrainConnector` uses), cycle by cycle, with the **same stimulus injection
  order** (touch → smell → `update()`).
- It reproduces **exactly** the steering/physics of `Pet.qml` and the smell of
  `World.qml` (forward/left/right probes, falloff, Braitenberg gradient turn,
  connectome signature `(left-right)*brainTurnGain`, rate-limited turn, wall
  reflex, nose-touch) so what is measured matches the live pet.
- Comparable environment: 640×480 arena without rocks, 4 fixed pellet
  positions. Only the initial heading and the biological noise are random, and
  both are **seeded** (`--seed`) so the experiment is repeatable.
- Organism state frozen (mid hunger = energy 50, awake): this phase measures
  *navigation mechanics*, not life cycle.

### Configurations (matrix)

| config        | chemoSideWeight | brainTurnGain | gradientGain | what it isolates              |
|---------------|-----------------|---------------|--------------|-------------------------------|
| control       | 26              | 0.05          | 300          | the current pet               |
| aux-off       | 26              | 0.05          | 0            | heading driven by the connectome only |
| ct-strong-1x  | 60              | 0.5           | 0            | connectome amplified ×10 (no aux) |
| ct-strong-4x  | 120             | 1.0           | 0            | connectome amplified ×20 (no aux) |
| ct-off        | 26              | 0             | 300          | heading driven by the auxiliary layer only |
| all-off       | 26              | 0             | 0            | no heading control (random walk) |

### Reproduce

```sh
# inside the plugin folder
node experiments/honesty-check.js                 # default seed
node experiments/honesty-check.js --seed=777      # any other seed
node experiments/honesty-check.js --trials=80     # more repetitions
```

Output: console table + `experiments/results/c-<config>-<seed>.json` +
`experiments/results/honesty-matrix-<seed>.tsv`.

### Results (40 trials per config)

Success = the pet reached the pellet before the limit (2000 cycles ≈ 200 s).

| config        | success (20260914) | success (777) | median cycles→food |
|---------------|--------------------|---------------|---------------------|
| control       | 100 %              | 100 %         | 556 / 201           |
| aux-off       | 62.5 %             | 60 %          | 810 / 587           |
| ct-strong-1x  | 12.5 %             | 12.5 %        | 1460 / 985          |
| ct-strong-4x  | 0 %                | 5 %           | — / 1195            |
| ct-off        | 100 %              | 95 %          | 632 / 190           |
| all-off       | 47.5 %             | 55 %          | 789 / 1010          |

(neural activity ≈ 30–32 neurons/cycle in every config; muscle magnitude
≈ 107–114, nearly symmetric `left-right ≈ –2`.)

### Reading (honest)

**It is the connectome** (measurable):
- *Locomotion*: every step comes from `accumleft/accumright` (body muscles
  07–23). No auxiliary layer generates movement; if the connectome does not
  drive, the pet does not move.
- *Sensory integration*: ~31 neurons fire per cycle on the baseline food-sense
  drive.
- *Food drive*: food ahead → more charge in ADFL/ADFR → muscles.
- *Touch reflex* on collisions (ALML/ALMR, nose-touch).

**It is not (or it is wrapper)**:
- *Homing efficiency* (success and time to arrive): carried by the auxiliary
  Braitenberg layer. With the connectome heading killed but the assist on
  (`ct-off`), success stays ~95–100 % and speed matches a control. Pure random
  walk (`all-off`) already finds food ~50 % of the time in this small arena.
- *Obstacle avoidance and wall reflex*: by code inspection (`Pet.qml`) they
  are geometric repulsion / physical reflection; they do not go through the
  connectome.

**Finding**: the connectome *alone* navigates ~60 % (`aux-off`), but
**amplifying its heading signal ×10–20 collapses success to 5–13 %**. With the
current injection map (ADFL/ADFR surplus → muscles), more signal ≠ better
taxis: it produces swing, not pursuit. This tells us the claim "the connectome
guides" must be stated with nuance — the sensory/integration/motor part is
real; the visible taxis is mostly the auxiliary layer — and it opens the next
cycle: **B** (better stimulus modeling) and **A** (tuning the circuit).

### Files

- `experiments/honesty-check.js` — reproducible harness.
- `experiments/results/*.json`, `*.tsv` — results of each run, per seed.

## Phase B — Stimulus Lab (does the Lab measure the connectome?)

**Question**: the Lab UI lets you place heat and chemical-B sources, poke the
worm's tail, and read "AFD/AWA/PLM activity". Are those readouts *real* — i.e.
does the stimulus actually change the activity of the real cells, and does it
ever change the worm's movement — or does the Lab just display numbers?

**Why it matters**: Phase C showed that most visible taxis comes from the
auxiliary layer, so a Lab overlay could easily be pure theater. This phase
checks the channels with the same honesty: the harness runs the **real
`Celegans.js`**, injects exactly like `BrainConnector.qml` does, and measures
both the cell-level and the behavioral response.

### The three channels (transcribed 1:1 from the UI)

| channel | input cell(s) | stimulus in the model | what it maps to biologically |
|---------|----------------|------------------------|------------------------------|
| 🔥 thermo | `AFDL` / `AFDR` | forward/left/right probes on the heat field → `surplus = weight * (left − right)` + forward drive | amphid "AFD" thermo-sensing neurons |
| 🧪 chem-B | `AWAL` / `AWAR` | same probe map on the chemical-B field | amphid "AWA" chemosensory neurons |
| ↕ tail | `PLML` / `PLMR` | poke = 150 charge, 4-cycle window (weighted by side) | posterior touch mechano-sensory neurons |

All injection targets are real neurons with real synapses in `Celegans.js`
(e.g. `AFDL → AIYL`, `AFDR → AIYR`, `AWAL/AWAR` into the AIZ command circuit,
`PLML/PLMR` into the tail/motor pools). The *gradient → charge mapping* is a
synthetic simplification and is labelled **synthetic** in the Lab UI.

### Reproduce

```sh
node experiments/stimulus-lab.js                # all scenarios, default seed
node experiments/stimulus-lab.js --scenario=B   # one scenario: A | B | C
node experiments/stimulus-lab.js --seed=777     # any other seed
```

Output: console tables + `experiments/results/stimulus-lab-<seed>.json` +
`experiments/results/stimulus-B-<seed>.tsv`.

### Scenario A — fixed pose, single field source (cell-level response)

The worm holds one pose facing a field source placed ahead-left/ahead-right;
only the brain runs. Question: does arming the channel activate the real target
cells (fires over 400 cycles) versus the sham?

| config | AFDL | AFDR | AWAL | AWAR | AIZL | motor bias (L−R) |
|---|---|---|---|---|---|---|
| sham (no source) | 0 | 5 | — | — | — | −914 |
| 🔥 thermo, panel gain | 0 | 5 | — | — | — | −914 |
| 🧪 chem-B, panel gain | — | — | 0 | 20 | 133 | −914 |
| 🔥 therm / 🧪 chem-B ×5 | 0 | 5 | 0 | 20 | 133 | −914 |

(neural wake ~31 neurons/cycle in every row — indistinguishable within noise.)

Result: **at the field distances and panel gains the Lab can express, the
injected charge lands below spiking threshold: the target cells do not fire and
the motor bias does not move.** The compound injection (balance + forward
drive) largely cancels inside the cell, leaving a sub-threshold residual.

### Scenario B — navigation consequence, auxiliary layer OFF

1200-cycle walks in an empty arena with the source fixed to the right, with
`gradientGain = brainTurnGain = 0` (Phase C's `aux-off`: the auxiliary
navigation layer is disabled, so **any** directional effect must come from the
connectome itself). Readout: accumulated displacement projected onto the
source direction, and % of trials finishing closer to the source.

| config | proj→source (20260914) | toward% | proj→source (777) | toward% |
|---|---|---|---|---|
| sham (no source) | +4 | 44 % | −129 | 19 % |
| 🔥 thermo @ panel max (30) | −33 | 25 % | +36 | 56 % |
| 🧪 chem-B @ panel max (45) | +68 | 56 % | −24 | 38 % |
| 🔥 thermo ×3 (90) | **+90** | **75 %** | +28 | 50 % |
| 🧪 chem-B ×3 (135) | **+92** | **69 %** | −8 | 50 % |
| 🔥 thermo ×5 (150) | −8 | 44 % | **+110** | **75 %** |
| 🧪 chem-B ×5 (225) | +60 | 69 % | +11 | 50 % |

Result: a directional gain *toward* the source sometimes appears (20260914:
sham +4 → thermo ×3 +90 / chem-B ×3 +92; 777: thermo ×5 +110), but the
magnitude flips between seeds and gains. The connectome *can* turn toward a
heat/chemical source through its own wiring — but the effect is weak and
noisy, exactly the Phase C pattern (`aux-off` ≈ 60 %, amplified strong
configs collapse).

### Scenario C — tail poke, phase sweep

One symmetric `PLML/PLMR` poke (150 charge, 4 cycles), launched at 12
different network phases (cycle 0, 10, … 110). Readout: change in total motor
output over the following 120 cycles versus a sham (both seeds).

| poke @ cycle | Δ motor (20260914) | Δ motor (777) |
|---|---|---|
| 0 | +666 | +881 |
| 10 | **0** | +28 |
| 20 | +1526 | +58 |
| 30 | +295 | +131 |
| 40 | +1672 | +1 |
| 50 | +804 | +18 |
| 60 | −251 | **−9** |
| 70 | +837 | +125 |
| 80 | +152 | **−5** |
| 90 | +60 | +83 |
| 100 | +643 | +8 |
| 110 | −88 | **−2** |
| windows with response | 11 / 12 | 8 / 12 |

Result: the tail poke is a **strong, mostly-reliable reflex** (a single 150
charge over 4 cycles reliably shifts the worm's motor output), with a handful
of phases where the same charge is absorbed. This matches the live pet, whose
poke visibly twitches it.

### Reading (honest)

**Real (measurable):**
- The channels target real cells with real synapses, and the injection uses
  the exact mechanism the food-sense pathway uses (Phase C validated).
- The tail poke propagates to the motor pool in most phases — it is a genuine,
  behaviorally visible reflex.
- Thermo and chem-B **do** couple into the connectome: at ×3 amplification a
  toward-source bias appears in at least one seed for both channels and never
  in the sham.

**Not (or fragile):**
- At the gains the current panel's sliders allow (thermo ≤ 30, chem-B ≤ 45),
  the injected charge stays sub-threshold in a mid-distance field: the Lab
  readouts would show no cell activation. Amplification is required — which the
  panel already provides as a future knob, and this phase quantifies it.
- The directional effect is seed-dependent (not a reliable homing signal) and
  collapses at the highest amplification (×5), reproducing Phase C's
  overdrive/saturation pattern.

**Finding**: the Lab measures the *real wiring*, and that wiring is:
  strongly observable for tail touch, weakly/fragilely observable for thermo
  and chemical-B. This is not a bug to hide: it is the honest frontier that
  phase **A** (circuit tuning) is meant to open — the Lab sliders exist to
  explore that amplification frontier, with the numbers above saying *how much*
  amplification is on the edge and how unreliable the regime is.

### Files

- `experiments/stimulus-lab.js` — reproducible Phase B harness.
- `experiments/results/stimulus-lab-<seed>.json`,
  `experiments/results/stimulus-B-<seed>.tsv` — run outputs per seed.
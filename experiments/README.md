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
- At the gains the current panel's sliders *alone* allow (thermo ≤ 30,
  chem-B ≤ 45), the injected charge stays sub-threshold in a mid-distance
  field: the Lab readouts would show no cell activation. Amplification is
  required — the live panel ships it as the **⚡ ×3 amplify** toggle, which maps
  **exactly** to the measured gains above (thermo 90, chem-B 135); a live
  probe → charge readout shows the sub-threshold picture instead of hiding it.
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

## Phase A — Circuit Lab (do real synapse edits change what the worm does?)

**Question**: the Circuit overlay edits the *actual wiring* — absolute weight
overrides per `FROM:TO` on the real `Celegans.js` connectome. Does rewiring
those synapses move (A) food-searching success in the aux-off regime, and
(B) the tail-touch reflex? Or does a patch set just change numbers in the UI?

**Why it matters**: Phase C and B showed the connectome alone navigates ~60 %
and that amplifying injected charge collapses taxis. Phase A is the direct
experiment: instead of turning up the *input*, we turn up the *synapses*. The
same honesty rules apply — the harness uses the **same patch engine** the UI
uses (`brain.setCircuitPatches`), so what is measured is what the live panel
would do.

### Method

- The introspector (`Brain.prototype.installCircuitPatches`) derives every real
  base weight by running each connectome entry against a scratch accumulator.
  Before anything is measured, a **self-check** confirms twelve known base
  weights (including a negative one, `AVL→MVL10 = −5`) and confirms two
  deliberately-absent pairs (`PLML→AVDR`, `ADFL→SMDVL`) read 0 — so "*NEW
  synapse*" in the editor really means base 0. The scanner found
  **3689 real synapses**; that list *is* the Circuit editor's source.
- Presets are transcribed 1:1 from the overlay; each is applied with
  `setCircuitPatches`, the exact engine the slider drags use.
- Scenario A reuses the Phase C aux-off walk (no auxiliary steering: only the
  wiring steers), N=40, seeded: success %, cycles, distance, spikes, L−R bias.
- Scenario B reuses the Phase B poke: one symmetric 150-charge `PLML/PLMR`
  poke at cycle 0/50/110, Δ motor over 120 cycles vs a sham poke, per config
  (a response is scored when |Δ motor| ≥ 25).

### Reproduce

```sh
node experiments/circuit-tuner.js                # scenarios A+B, default seed
node experiments/circuit-tuner.js --scenario=A   # one scenario | B | all
node experiments/circuit-tuner.js --seed=777     # any other seed
```

Output: console tables + `experiments/results/circuit-tuner-<seed>.json` +
`experiments/results/circuit-A-<seed>.tsv`. A failed base-weight self-check
aborts the run.

### Scenario A — patches vs. food-searching (aux OFF), 40 trials/apron

| config | success% | medCyc | meanCyc | dist px | spk/cyc | meanLR |
|---|---|---|---|---|---|---|
| control | 52.5 % | — | 1478 | 1907 | 31.64 | −2.28 |
| chemotaxis ↑ | 50 % | — | 1599 | 2075 | 32.18 | −2.29 |
| escape kick | 55 % | — | 1421 | 1834 | 31.61 | −2.27 |
| chemo shortcut (new) | 47.5 % | — | 1570 | 2034 | 32.00 | −2.32 |
| calm touch | 47.5 % | — | 1409 | 1823 | 31.61 | −2.24 |
| all presets | 55 % | — | 1416 | 1843 | 32.30 | −2.37 |

(seed 20260914; median cycles-to-food empty — in aux-off most trials time out,
mirroring Phase C.)

### Scenario B — tail poke burst, patched vs. control (seed 20260914)

| config | Δmotor @0 | Δmotor @50 | Δfwd @50 | reflex@0/50/110 |
|---|---|---|---|---|
| control | +666 | +804 | +160 | yes/yes/yes |
| chemotaxis ↑ | −1128 | −1712 | −296 | yes/yes/yes |
| escape kick | −877 | −469 | +321 | yes/yes/yes |
| chemo shortcut | +1241 | +738 | −296 | yes/yes/yes |
| calm touch | +666 | +1017 | +263 | yes/yes/yes |
| all presets | +474 | −8 | +94 | yes/—/yes |

### Reading (honest)

**Real and measurable:**
- The editor is not guessing: the introspector recovered the actual base
  weights (3689 synapses, negative weights included), so every "patched" label
  is a real electrical change and every "NEW" label is base 0 (new wiring).
  Two presets deliberately add connections (the chemo shortcut, and the
  escape kick's `PLML→AVDR`); the harness measures those as outright new wires.
- Scenario B shows the patches are **not inert on the motor**: escape and
  chemotaxis flip the sign of the poke burst within the response window (the
  rewired pool debounces the poke instead of adding to it), and "all presets"
  mutes the mid-window response. The same poke lands on a rewired brain and the
  observable changes in the same seeded run.
- Scenario A is a clean negative within this run: none of the presets moves
  aux-off food-searching (47.5–55 % vs 52.5 % control; distance/spikes flat).

**Not (or fragile):**
- These presets, at these weights, in one seed and N=40 trials, do not create a
  better hunter. Given Phase C (amplification collapses taxis, circuit very
  dissipative) and Phase B (directional effects seed-dependent), a handful of
  ±4–16 weight edits is a small change against a noisy ~50 % baseline: the
  honest statement is *any* single-synapse rescue is unproven and likely weak.
- The Scenario B shifts are seed-sized observations, not a recipe: the reflex
  window remains present in every config (only its sign/shape moves), and no
  config reliably amplifies the burst.

**Finding**: the Circuit Lab exposes the real wiring honestly, but the wiring
is a blunt instrument at the tested scale — small patch sets do not rescue
navigation, and they reshape (rather than strengthen) the touch reflex. The
harness is the referee: rerun it `--seed=<n>` before believing any claimed
"better worm". The open question this phase leaves is *scale* — whether larger,
graded weights on the chemo chain beat the noise the way ×3 amplification
reliably did not.

### Files

- `experiments/circuit-tuner.js` — reproducible Phase A harness.
- `experiments/results/circuit-tuner-<seed>.json`,
  `experiments/results/circuit-A-<seed>.tsv` — run outputs per seed.

## Living-plugin notes (made the honest results visible, not faked)

These changes exist so a curious non-technical user can SEE whether a stimulus
or a wiring edit did anything, without reading JavaScript:

- **Pet life pauses with the panel.** Energy/sleep/food only tick while the
  panel is open (`PetState.lifeActive`, `World.live` + the auto feeder bound to
  `root.opened`). Closing the plugin no longer starves the pet overnight; an
  open-again pet is exactly where you left it.
- **Tail poke is now visible.** Each poke flashes the body (`Pet.flashStartle`)
  on top of the real (subtle) motor response from the wiring.
- **Thermo / chemical-B show the honest sub-threshold picture.** The Lab reads
  live `probe → charge` for both channels, plus a hint line ("crank the slider
  higher") when charge is present but no cell fires yet — and the **⚡ ×3
  amplify** toggle maps exactly onto the measured ×3 gains (thermo 90,
  chem-B 135) where the harness saw a real taxis response.
- **Applied circuits are visible in the HUD.** A 🧬 chip next to the name shows
  how many patches are live from pet.json, so an applied edit is obvious even
  with the Circuit overlay closed.
- **Circuit editor search & restore.** A filter box narrows the synapse list to
  the ones involving a typed cell (presets that don't touch it are dimmed), and
  "■ end & restore" now rebuilds the editor from the restored wiring — the
  window reflects exactly what the pet runs again.
- **Journal load/delete.** Every saved experiment has explicit ↺ re-apply and
  🗑 delete buttons (no hidden tap-to-reapply).
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
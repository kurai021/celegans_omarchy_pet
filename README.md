# C. elegans Pet

A virtual pet for Omarchy Linux based on the real connectome of the nematode *Caenorhabditis elegans*.

## 🪱 What is it?

This plugin implements a simplified simulation of the C. elegans nervous system, allowing a virtual pet to interact with its environment (the panel window) and the user based on signal propagation through a graph of neurons and synapses.

## 🚀 Installation

```sh
omarchy plugin add https://github.com/kurai021/celegans-pet.git --enable
```

## 🕹️ Usage

- **Open**: Click the `🪱 Pet` button in the Omarchy bar.
- **Interaction**: 
  - **Touch**: Click on the worm's body to stimulate its tactile neurons.
  - **Move**: You can manually drag the pet across the window.
  - **Feed**: Click on the empty water to drop a food pellet. The pet smells it and turns toward it through its chemo neurons (real chemotaxis), and eats when the nose reaches the pellet. How hard it hunts follows its appetite: a starving pet beelines to food, while a sated one (energy above ~90) ignores it and just ambles, only eating what it stumbles into — wait for it to get hungry again to feed it.
- **Behavior**: The pet explores the space automatically, curving smoothly around walls and obstacles (no hardcoded turns — heading changes toward a geometrically computed escape direction). It gets hungry, gets sleepy, naps on its own, and speaks phrases according to its state (`{name}` is replaced by the configured name). Name, energy, sleep drive and lifetime stats persist between restarts.
- **Status chip**: A fixed chip under the name always shows the pet's *derived* state (`💤 sleeping`, `😾 grumpy`, `🍎 hunting`, `🍽️ hungry`, `😌 full`, `🌿 resting`, `🔍 exploring`). Every label is backed by a real model signal, never invented: sleep is the actual nap, hunger matches the `< 55` auto-feed cutoff, hunting means food is smelt *while* the appetite is active, full is the `> 90` rule that stops hunting, resting requires ~4 s without movement (not a couple of still frames), and grumpy is a real user touch in the last 2.5 s. One-off reactions (ouch, sleepy, meal...) stay in the speech bubble.
- **Naming**: On first run (no saved name and no CLI seed) a small card asks you what to call the pet. Afterwards, click the ✏️ next to the name to rename it inline (Enter commits, Esc cancels).
- **Name precedence**: `pet.json` is the single source of truth for the name. The CLI `petName` setting only seeds a name while the pet has never been named; once a name is persisted or set in the UI, an old setting value can never overwrite it.
- **Learning (hand means food)**: Feed the pet by *clicking the empty water right after poking it* and it slowly learns that your hand brings food. After enough hand-fed moments (`memory.handToFood`) it plays a one-time **🧠 "learned something"** message, and from then on each touch primes it to expect food for a few seconds — it homes in harder and wanders less right after you touch it. It never "moves toward your cursor"; the learned anticipation only modulates the food drive/chemotaxis it already has. The association and the habit fade slowly if you stop reinforcing them, while the one-time insight stays.
- **Habituation to touch**: Touching stays *unpleasant* — the pet still recoils, grumbles, and keeps its negative valence. But the more it is handled, the more the tactile stimulus loses its alarm: over ~10 touches the response decays to a ~35% floor and its protests soften from "Don't touch me!" to "Okay, okay. Not scary anymore." (still not a hug). Sensitivity slowly recovers if you leave it alone.
- **Memory persistence**: everything above lives in `memory` in `pet.json` and survives restarts. Old `pet.json` files without `memory` load unchanged (defaults apply); `mealSites` is reserved for a future spatial-memory phase.

## ⚙️ Configuration

There is no settings form for bar widgets yet; widget settings live in the
inline entry in `~/.config/omarchy/shell.json` and are declared by the
`barWidget.schema` block in `manifest.json`. Change them from a terminal:

```sh
omarchy bar set io.github.kurai021.celegans-pet petName Citrus
```

`omarchy bar set <id> <key> <value>` writes the key through the shell's IPC and
is picked up live (no plugin reload or shell restart needed). Use `--json` for
values that are not plain strings.

For `petName`, the CLI setting only applies as a **seed** while the pet has
never been named (no `petName`/`everNamed` in `pet.json` yet). Once the pet has
a persisted name it wins, so an old setting cannot undo a rename — renaming
from the ✏️ in the panel keeps both `pet.json` and the setting in sync.

Persisted pet state (name, energy, sleep drive, stats) lives in
`~/.local/state/io.github.kurai021.celegans-pet/pet.json`.

## 🛠️ Technical Details

The plugin uses:
- **BrainConnector.qml**: Acts as the bridge between the logical simulation and the view.
- **celegans.js**: Contains the connectome implementation, managing neuron states and membrane potential updates.
- **PetVisual.qml**: Draws the pet using a QML `Canvas`, creating a sinusoidal undulating effect that varies according to motor activity.

## ⚖️ License

This project is licensed under the **GNU GPL v3**.

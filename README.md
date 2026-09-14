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
  - **Feed**: Click on the empty water to drop a food pellet. The pet smells it and turns toward it through its chemo neurons (real chemotaxis), and eats when the nose reaches the pellet.
- **Behavior**: The pet explores the space automatically, curving smoothly around walls and obstacles (no hardcoded turns — heading changes toward a geometrically computed escape direction). It gets hungry, gets sleepy, naps on its own, and speaks phrases according to its state (`{name}` is replaced by the configured name). Name, energy, sleep drive and lifetime stats persist between restarts.

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

Persisted pet state (name, energy, sleep drive, stats) lives in
`~/.local/state/io.github.kurai021.celegans-pet/pet.json`.

## 🛠️ Technical Details

The plugin uses:
- **BrainConnector.qml**: Acts as the bridge between the logical simulation and the view.
- **celegans.js**: Contains the connectome implementation, managing neuron states and membrane potential updates.
- **PetVisual.qml**: Draws the pet using a QML `Canvas`, creating a sinusoidal undulating effect that varies according to motor activity.

## ⚖️ License

This project is licensed under the **GNU GPL v3**.

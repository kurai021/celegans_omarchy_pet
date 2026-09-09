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
- **Behavior**: The pet explores the space automatically. When it hits the window edges, the nervous system processes the stimulus and generates a motor response to turn and continue exploring.

## 🛠️ Technical Details

The plugin uses:
- **BrainConnector.qml**: Acts as the bridge between the logical simulation and the view.
- **celegans.js**: Contains the connectome implementation, managing neuron states and membrane potential updates.
- **PetVisual.qml**: Draws the pet using a QML `Canvas`, creating a sinusoidal undulating effect that varies according to motor activity.

## ⚖️ License

This project is licensed under the **GNU GPL v3**.

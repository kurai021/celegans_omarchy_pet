import QtQuick
import Quickshell
import Quickshell.Io

// Persisted pet memory: name, energy, sleep drive and lifetime stats.
// Lives in ~/.local/state/<id>/pet.json (FileView) so the pet survives
// shell reloads and restarts. Values are stored in the open format so
// nothing is lost when the file is missing/corrupt.
Item {
  id: state

  // --- persistent state ---------------------------------------------------
  property real startEnergy: 65       // fresh-pet energy: green, not full, hungry
  // pet.json is the single source of truth for the name. everNamed flips true
  // once the name is persisted or explicitly set, which permanently disables
  // the CLI setting as a seed (it can never re-overwrite pet.json).
  property string petName: "Wormy"
  property bool everNamed: false
  property real energy: startEnergy   // 0..100 (0 = starving, >90 = "full")
  property real sleepiness: 0       // 0..1 (1 = ready to sleep)
  property bool asleep: false
  // The pet is only "alive" while the panel is open. The host binds this to
  // the panel's opened state; while false, energy and sleep drive freeze so
  // closing the app PAUSES the pet instead of starving it in the background.
  property bool lifeActive: true
  property var stats: { "distance": 0, "startled": 0, "meals": 0 }

  // --- learned memory (F2) ------------------------------------------------
  // handToFood   : how often food appeared right after the user touched
  //                (grows +1 per hand-feed right after a touch, decays slowly)
  // touchExposure: accumulated user touches; drives habituation (response
  //                scale shrinks toward a floor, tone softens, but the touch
  //                stays unpleasant / negative)
  // learnedOnce  : one-shot flag for the "I learned something" narrative;
  //                the association itself keeps strengthening/decaying
  // mealSites    : reserved for the future spatial-memory phase (F5); empty
  //                for now. Persisted additively so old pet.json files load.
  property var memory: { "handToFood": 0, "touchExposure": 0, "learnedOnce": false, "mealSites": {} }

  // --- applied circuit (Phase A) -------------------------------------------
  // Synapse patches the user committed with "apply to pet" in the Circuit Lab.
  // Array of {from,to,weight} (absolute weight overrides on real synapses).
  // Lives in pet.json because it IS part of the pet: it survives sessions,
  // reloads and restarts; the overlay only edits an isolated session copy.
  // Applied circuit patches (pet.json). Assignments emit the built-in
  // `circuitChanged` property-change signal (BrainConnector seeds the live
  // brain from it; the Circuit overlay listens and skips while editing).
  property var circuit: []

  // --- tuning (learning) --------------------------------------------------
  property real handToFoodLearnThreshold: 5   // hand->food experiences to "get it"
  property real handToFoodCap: 12             // soft cap so it can't runaway
  property real handToFoodDecayPerSec: 1 / 240   // loses ~1 point / 4 min idle
  property real touchExposureDecayPerSec: 1 / 600 // loses ~1 / 10 min idle
  property real touchResponseFloor: 0.35         // habituated floor (>0: still feels it)

  // --- tuning -------------------------------------------------------------
  property real activeDrainPerSec: 0.12     // energy drained / s while moving
  property real idleDrainPerSec: 0.02       // energy drained / s while resting
  property real sleepDrivePerSec: 1 / 540   // full sleep drive in ~9 min awake

  signal changed()

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string dir: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/io.github.kurai021.celegans-pet"
  readonly property string filePath: dir + "/pet.json"

  Process { id: mkdir; command: ["mkdir", "-p", state.dir] }
  Component.onCompleted: mkdir.running = true

  FileView {
    id: file
    path: state.filePath
    watchChanges: true
    printErrors: false
    onFileChanged: state.reload()
    onLoaded: state.reload()
    onLoadFailed: state.changed() // no file yet -> keep defaults
  }

  function reload() {
    try {
      var d = JSON.parse(String(file.text() || ""));
      if (d && typeof d === "object") {
        // A persisted name makes the pet "named" no matter what the setting
        // says; a stored petName also implies everNamed for legacy saves.
        if (d.everNamed !== undefined) everNamed = !!d.everNamed;
        if (d.petName !== undefined) {
          petName = String(d.petName);
          if (!everNamed) everNamed = true;
        }
        if (d.energy !== undefined) energy = Math.max(0, Math.min(100, Number(d.energy)));
        if (d.sleepiness !== undefined) sleepiness = Math.max(0, Math.min(1, Number(d.sleepiness)));
        if (d.asleep !== undefined) asleep = !!d.asleep;
        if (d.stats && typeof d.stats === "object") {
          if (d.stats.distance !== undefined) stats.distance = Number(d.stats.distance) || 0;
          if (d.stats.startled !== undefined) stats.startled = Number(d.stats.startled) || 0;
          if (d.stats.meals !== undefined) stats.meals = Number(d.stats.meals) || 0;
        }
        // Learned memory is additive: a pet.json without `memory` keeps the
        // fresh defaults, so very old saves keep working untouched.
        if (d.memory && typeof d.memory === "object") {
          if (d.memory.handToFood !== undefined)
            memory.handToFood = Math.max(0, Math.min(state.handToFoodCap, Number(d.memory.handToFood) || 0));
          if (d.memory.touchExposure !== undefined)
            memory.touchExposure = Math.max(0, Number(d.memory.touchExposure) || 0);
          if (d.memory.learnedOnce !== undefined) memory.learnedOnce = !!d.memory.learnedOnce;
          if (d.memory.mealSites !== undefined && typeof d.memory.mealSites === "object")
            memory.mealSites = d.memory.mealSites;
        }
        // Applied circuit patches; additive like memory, so old saves load.
        if (d.circuit !== undefined && Array.isArray(d.circuit)) {
          var applied = []
          for (var c = 0; c < d.circuit.length; c++) {
            var ce = d.circuit[c]
            if (ce && typeof ce.from === "string" && typeof ce.to === "string"
                && typeof ce.weight === "number") applied.push(ce)
          }
          circuit = applied
          circuitChanged()
        }
      }
    } catch (e) { /* keep current values on malformed JSON */ }
    changed();
  }

  // UI rename: applies unconditionally (the pet is already named at this
  // point); persists to pet.json, the single source of truth.
  function setName(name) {
    var trimmed = String(name || "").trim();
    if (!trimmed) return "";
    petName = trimmed;
    everNamed = true;
    save();
    changed();
    return trimmed;
  }

  // CLI-setting seed: refuses to overwrite a persisted name. This is the one
  // rule behind every rename path, so event order can never cause the setting
  // to hijack pet.json.
  function seedName(name) {
    if (everNamed) return "";
    return setName(name);
  }

  // A user touch just happened. Accumulates exposure (habituation) and
  // returns the response scale (1 = fully reactive, -> touchResponseFloor as
  // exposure grows). Avoidance keeps its negative valence either way.
  function recordTouch() {
    memory.touchExposure = Math.min(60, (Number(memory.touchExposure) || 0) + 1);
    save();
    changed();
    return touchResponseScale();
  }

  // How strongly a touch lands on the connectome after `touchExposure`
  // touches. Exponential habituation that floors at touchResponseFloor: the
  // pet never becomes indifferent, it just stops being alarmed.
  function touchResponseScale() {
    var e = Number(memory.touchExposure) || 0;
    return Math.max(state.touchResponseFloor, Math.pow(0.9, e));
  }

  // A user-dropped pellet appeared right after a hand touch: +1 hand->food
  // experience. Returns true the FIRST time the association crosses the
  // learning threshold (once per pet lifetime -> the narrative event).
  function recordHandFood() {
    memory.handToFood = Math.min(state.handToFoodCap, (Number(memory.handToFood) || 0) + 1);
    var first = !memory.learnedOnce && memory.handToFood >= state.handToFoodLearnThreshold;
    if (first) memory.learnedOnce = true;
    save();
    changed();
    return first;
  }

  // Idle decay so memories stay memories: without reinforcement both the
  // hand->food association and the habituation slowly fade (real time, even
  // while the panel is closed). Only Writes through throttle when something
  // actually changed.
  function decayMemory(seconds) {
    var changedFlag = false;
    var h = Number(memory.handToFood) || 0;
    if (h > 0) {
      var nh = Math.max(0, h - state.handToFoodDecayPerSec * seconds);
      if (nh !== h) { memory.handToFood = nh; changedFlag = true; }
    }
    var t = Number(memory.touchExposure) || 0;
    if (t > 0) {
      var nt = Math.max(0, t - state.touchExposureDecayPerSec * seconds);
      if (nt !== t) { memory.touchExposure = nt; changedFlag = true; }
    }
    if (changedFlag) save();
  }

  // Throttle disk writes: state changes every simulation cycle.
  function save() {
    saveTimer.restart()
  }

  // "Apply to pet" from the Circuit Lab: persist the committed patch list and
  // tell anyone listening (BrainConnector seeds the live brain from it).
  function setCircuit(list) {
    var applied = []
    list = list || []
    for (var i = 0; i < list.length; i++) {
      var e = list[i]
      if (e && typeof e.from === "string" && typeof e.to === "string"
          && typeof e.weight === "number") applied.push({ from: e.from, to: e.to, weight: e.weight })
    }
    circuit = applied
    circuitChanged()
    save()
    changed()
    return applied
  }

  Timer {
    id: saveTimer
    interval: 2000
    onTriggered: {
      // The name is only persisted once the pet is actually named. Until
      // then (first run, onboarding not finished) pet.json deliberately has
      // no petName, so an anonymous pet cannot silently become "Wormy" and
      // the onboarding keeps showing on the next open.
      var payload = {
        energy: state.energy,
        sleepiness: state.sleepiness,
        asleep: state.asleep,
        stats: { distance: state.stats.distance, startled: state.stats.startled, meals: state.stats.meals },
        memory: {
          handToFood: state.memory.handToFood,
          touchExposure: state.memory.touchExposure,
          learnedOnce: state.memory.learnedOnce,
          mealSites: state.memory.mealSites
        },
        circuit: state.circuit
      };
      if (state.everNamed) {
        payload.petName = state.petName;
        payload.everNamed = true;
      }
      file.setText(JSON.stringify(payload, null, 2) + "\n");
    }
  }

  // Aging while the pet is asleep or the panel is closed is suspended (see
  // `lifeActive`): the worm pauses when you stop looking at it. Memories
  // still decay in real time so learned habits stay time-sensitive.
  Timer {
    interval: 1000
    running: true
    repeat: true
    onTriggered: {
      if (state.lifeActive && !state.asleep) {
        state.energy = Math.max(0, state.energy - 1 / 300); // -1 point / 5 min
        if (state.energy <= 0) state.changed();
      }
      state.decayMemory(1); // memories fade (or stay) in real time
    }
  }

  // Called from Pet on every simulation cycle with the elapsed sim time
  // (ms) and whether the pet is actively crawling.
  function tick(dtMs, moving) {
    if (state.asleep) return
    var s = dtMs / 1000
    var drain = (moving ? state.activeDrainPerSec : state.idleDrainPerSec) * s
    state.energy = Math.max(0, state.energy - drain)
    state.sleepiness = Math.min(1, state.sleepiness + state.sleepDrivePerSec * s)
    state.save()
  }

  function addMeal() { stats.meals++; energy = Math.min(100, energy + 35); save(); changed() }
  function addDistance(meters) { stats.distance += meters; }
  function addStartle() { stats.startled++; save(); }
  function goSleep() { asleep = true; save(); changed() }
  function wake() { asleep = false; sleepiness = 0.05; energy = Math.min(100, energy + 8); save(); changed() }
}
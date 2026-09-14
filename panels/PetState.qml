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
  property var stats: { "distance": 0, "startled": 0, "meals": 0 }

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

  // Throttle disk writes: state changes every simulation cycle.
  function save() {
    saveTimer.restart()
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
        stats: { distance: state.stats.distance, startled: state.stats.startled, meals: state.stats.meals }
      };
      if (state.everNamed) {
        payload.petName = state.petName;
        payload.everNamed = true;
      }
      file.setText(JSON.stringify(payload, null, 2) + "\n");
    }
  }

  // Even with the panel closed the pet ages slowly in the background, so
  // energy things while you're away (gently).
  Timer {
    interval: 1000
    running: true
    repeat: true
    onTriggered: {
      if (!state.asleep) {
        state.energy = Math.max(0, state.energy - 1 / 300); // -1 point / 5 min
        if (state.energy <= 0) state.changed();
      }
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
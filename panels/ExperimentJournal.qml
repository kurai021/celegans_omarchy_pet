import QtQuick
import Quickshell
import Quickshell.Io

// Phase B: persistent record of Lab experiments. Lives in
// ~/.local/state/<id>/experiment-journal.json — a SEPARATE file from pet.json
// on purpose: the journal is what WE learned about the pet (strings + configs
// + observed signals), while pet.json is what the pet remembers about its own
// life. Reassigning `entries` triggers the UI; nothing here feeds back into
// the simulation.
Item {
  id: journal

  property var entries: []          // newest first: {id,date,type,hypothesis,config,results,observation}

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string dir: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/io.github.kurai021.celegans-pet"
  readonly property string fileName: dir + "/experiment-journal.json"

  Process { id: mkdir; command: ["mkdir", "-p", journal.dir] }
  Component.onCompleted: mkdir.running = true

  FileView {
    id: file
    path: journal.fileName
    watchChanges: true
    printErrors: false
    onFileChanged: journal.reload()
    onLoaded: journal.reload()
    onLoadFailed: journal.entriesChanged() // no journal yet -> empty list
  }

  function reload() {
    try {
      var d = JSON.parse(String(file.text() || ""))
      if (d && typeof d === "object" && d.entries && d.entries.length !== undefined)
        journal.entries = d.entries.slice()
    } catch (e) { /* keep current entries on malformed JSON */ }
    journal.entriesChanged()
  }

  // Append an experiment (config + whatever we observed) and persist.
  function add(entry) {
    var e = entry || {}
    var next = {
      "id": (journal.entries.length ? journal.entries[journal.entries.length - 1].id : 0) + 1,
      "date": Date.now(),
      "type": e.type || "stimulus",
      "hypothesis": String(e.hypothesis || ""),
      "config": e.config || {},
      "results": e.results || {},
      "observation": String(e.observation || "")
    }
    var list = journal.entries.concat([next])
    journal.entries = list
    journal.save()
    return next
  }

  function save() {
    var payload = { "version": 1, "entries": journal.entries }
    file.setText(JSON.stringify(payload, null, 2) + "\n")
  }

  function count() { return journal.entries.length }
  function at(i) { return journal.entries[i] }
}
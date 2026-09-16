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

  // Append an experiment (config + whatever we observed) and persist. New
  // entries land at the FRONT so the newest is always the first the panel
  // shows (the list renders in array order).
  function add(entry) {
    var e = entry || {}
    var maxId = 0
    for (var i = 0; i < journal.entries.length; i++)
      if (journal.entries[i].id > maxId) maxId = journal.entries[i].id
    var next = {
      "id": maxId + 1,
      "date": Date.now(),
      "type": e.type || "stimulus",
      "hypothesis": String(e.hypothesis || ""),
      "config": e.config || {},
      "results": e.results || {},
      "observation": String(e.observation || "")
    }
    journal.entries = [next].concat(journal.entries)
    journal.save()
    return next
  }

  function save() {
    var payload = { "version": 1, "entries": journal.entries }
    file.setText(JSON.stringify(payload, null, 2) + "\n")
  }

  function count() { return journal.entries.length }
  function at(i) { return journal.entries[i] }

  // --- move-one up/down (▲/▼ reorder buttons in the panels) -------------------
  function findIndex(id) {
    for (var i = 0; i < journal.entries.length; i++)
      if (journal.entries[i].id === id) return i
    return -1
  }

  // Swap the entry with `id` one position up (-1) or down (+1) and persist.
  // Unknown ids and edges are no-ops.
  function moveBy(id, delta) {
    var cur = journal.findIndex(id)
    if (cur < 0 || delta === 0) return
    var to = cur + delta
    if (to < 0 || to >= journal.entries.length) return
    var arr = journal.entries.slice()
    var e = arr.splice(cur, 1)[0]
    arr.splice(to, 0, e)
    journal.entries = arr
    journal.save()
  }

  // Delete one entry by id and persist. Unknown ids are ignored.
  function remove(id) {
    var list = []
    for (var i = 0; i < journal.entries.length; i++) {
      if (journal.entries[i].id !== id) list.push(journal.entries[i])
    }
    if (list.length === journal.entries.length) return
    journal.entries = list
    journal.save()
  }
}
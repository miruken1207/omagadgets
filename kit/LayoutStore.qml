import QtQuick
import Quickshell
import Quickshell.Io

// Where each gadget sits, and whether edit mode is on. Shared by every
// monitor's window, so a card dragged on one screen moves on all of them.
Item {
  id: store

  readonly property string home: Quickshell.env("HOME")

  // ---- layout: each card's centre (fractions of the screen) and scale,
  // read from omagadgets.json; a card with no entry sits at its default.
  property var layout: ({})

  FileView {
    id: layoutFile
    path: store.home + "/.config/omarchy/omagadgets.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var data = JSON.parse(text())
        store.layout = data && typeof data === "object" ? data : ({})
      } catch (e) {
        store.layout = ({})
      }
    }
    onLoadFailed: store.layout = ({})
  }

  function writeLayout(next) {
    store.layout = next
    layoutFile.setText(JSON.stringify(next, null, 2) + "\n")
  }

  function saveCard(key, entry) {
    var next = Object.assign({}, store.layout)
    next[key] = entry
    writeLayout(next)
  }

  function resetCard(key) {
    var next = Object.assign({}, store.layout)
    delete next[key]
    writeLayout(next)
  }

  // Edit mode lives in a flag file so a keybinding can flip it with a plain
  // shell script (omagadgets-edit, shipped with the plugin), no IPC involved.
  property bool editing: false

  FileView {
    id: editFlag
    path: store.home + "/.local/state/omagadgets/editing"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: store.editing = text().trim() === "1"
    onLoadFailed: store.editing = false
  }

  function finishEditing() {
    store.editing = false
    editFlag.setText("0\n")
  }
}

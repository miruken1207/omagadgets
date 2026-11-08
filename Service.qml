import QtQuick
import Quickshell
import Quickshell.Io
import "kit"
import "Settings.js" as Settings

// omagadgets: glass desktop gadgets (clock, weather, hardware, now playing,
// calendar) on one workspace, draggable and resizable in edit mode.
//
// This service only reads the settings and opens a window per monitor
// (GadgetsWindow.qml). Each gadget lives on its own in gadgets/<id>/, and
// the pieces they share are in kit/.
Item {
  id: root

  // ---- injected by the shell
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null
  property var pluginRegistry: null

  readonly property string pluginId: manifest && manifest.id ? String(manifest.id) : "miruken1207.omagadgets"

  // ---- settings
  // Settings live inline on this plugin's entry in shell.json. Third-party
  // services aren't handed the shell config, so read the file and follow it.
  property var entry: ({})
  readonly property var settings: Settings.resolveSettings(root.entry)

  FileView {
    path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/omarchy/shell.json"
    watchChanges: true
    onFileChanged: reload()
    onLoaded: root.entry = Settings.findEntry(text(), root.pluginId)
    onLoadFailed: root.entry = ({})
  }

  // ---- layout and edit mode, shared by every monitor
  LayoutStore {
    id: layoutStore
  }

  // ---- one surface per monitor
  Variants {
    model: Quickshell.screens

    GadgetsWindow {
      settings: root.settings
      store: layoutStore
    }
  }
}

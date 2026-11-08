import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "kit"
import "Settings.js" as Settings
// Gadgets are loaded by URL (see GadgetSlot), but Quickshell only registers
// the QML types of directories it reaches through import statements, so
// list every gadget directory here for their own helper components to resolve.
import "gadgets/clock"
import "gadgets/weather"
import "gadgets/hardware"
import "gadgets/media"
import "gadgets/calendar"
import "gadgets/rates"

// One full-screen surface per monitor on the Bottom layer (above the
// wallpaper, under windows), shown while that monitor's active workspace is
// the configured one.
//
// Gadget contract: each gadget is a self-contained component in
// gadgets/<id>/<Id>.qml that only imports kit/. The window hands it `host`
// ({ u, active, editing, options }) and reads back `defaultX` / `defaultY`
// (its centre before the user moves it, as fractions of the screen) and
// `clickArea` (the item that takes clicks outside edit mode, or null).
PanelWindow {
  id: surface

  required property var modelData
  property var settings: Settings.resolveSettings({})
  property var store: null

  screen: modelData

  readonly property var hyprMonitor: Hyprland.monitorFor(modelData)
  readonly property bool shown: !!(hyprMonitor && hyprMonitor.activeWorkspace
    && hyprMonitor.activeWorkspace.name === settings.workspace)
  readonly property bool editing: !!store && store.editing && shown

  // Everything is sized in hundredths of the screen height.
  readonly property real u: height / 100

  anchors { top: true; bottom: true; left: true; right: true }
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.layer: WlrLayer.Bottom
  WlrLayershell.namespace: "miruken1207-omagadgets"
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

  // Clicks fall through to the desktop except on each gadget's clickArea,
  // and everywhere while editing.
  property Region clickInput: Region {
    regions: [clockSlot.region, weatherSlot.region, hardwareSlot.region, mediaSlot.region, calendarSlot.region, ratesSlot.region]
  }
  mask: editing ? null : clickInput
  visible: shown || content.opacity > 0

  // A gadget in its draggable slot, loaded only while enabled. `window` is
  // passed in rather than reached by id from inside the inline component.
  component GadgetSlot: CardSlot {
    id: gadgetSlot

    property var window: null
    property string gadget: ""
    readonly property bool enabledHere: !!window && window.settings.gadgets.indexOf(gadget) !== -1

    readonly property QtObject host: QtObject {
      readonly property real u: gadgetSlot.window ? gadgetSlot.window.u : 10
      readonly property bool active: !!gadgetSlot.window && gadgetSlot.window.shown
      readonly property bool editing: !!gadgetSlot.window && gadgetSlot.window.editing
      readonly property var options: gadgetSlot.window ? gadgetSlot.window.settings.options[gadgetSlot.gadget] || ({}) : ({})
    }

    readonly property Region region: Region {
      item: loader.item && loader.item.clickArea ? loader.item.clickArea : null
    }

    store: window ? window.store : null
    key: gadget
    visible: enabledHere
    defaultX: loader.item ? loader.item.defaultX : 0.5
    defaultY: loader.item ? loader.item.defaultY : 0.5

    Loader {
      id: loader
      active: gadgetSlot.enabledHere
      source: Qt.resolvedUrl(Settings.entryFile(gadgetSlot.gadget))
      onLoaded: item.host = gadgetSlot.host
    }
  }

  Item {
    id: content
    anchors.fill: parent
    opacity: surface.shown ? 1 : 0
    scale: surface.shown ? 1 : 0.97
    Behavior on opacity { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
    Behavior on scale { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }

    EditBanner {
      z: 2
      visible: surface.editing
      u: surface.u
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: parent.top
      anchors.topMargin: Math.round(surface.u * 5)
      onDone: surface.store.finishEditing()
    }

    GadgetSlot { id: clockSlot; gadget: "clock"; window: surface; area: content }
    GadgetSlot { id: weatherSlot; gadget: "weather"; window: surface; area: content }
    GadgetSlot { id: hardwareSlot; gadget: "hardware"; window: surface; area: content }
    GadgetSlot { id: mediaSlot; gadget: "media"; window: surface; area: content }
    GadgetSlot { id: calendarSlot; gadget: "calendar"; window: surface; area: content }
    GadgetSlot { id: ratesSlot; gadget: "rates"; window: surface; area: content }
  }
}

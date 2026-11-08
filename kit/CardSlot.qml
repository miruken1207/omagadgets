import QtQuick
import qs.Commons as Commons

// A card placed by its centre and scaled around it. In edit mode it can be
// dragged, scaled from the corner handle (proportionally, around its
// centre) and put back to its default place and size with a double click.
Item {
  id: slot

  property var store: null
  property string key: ""
  property Item area: null
  property real defaultX: 0.5
  property real defaultY: 0.5
  default property alias body: holder.data

  readonly property bool editing: !!store && store.editing
  readonly property color accent: Commons.Color.accent

  readonly property var saved: store ? store.layout[key] || null : null
  readonly property real centerX: saved && typeof saved.x === "number" ? saved.x : defaultX
  readonly property real centerY: saved && typeof saved.y === "number" ? saved.y : defaultY
  readonly property real savedScale: saved && typeof saved.scale === "number" ? saved.scale : 1

  // Live state while the mouse is down; folded into the layout on release.
  property point dragOffset: Qt.point(0, 0)
  property real liveScale: -1
  readonly property real cardScale: liveScale > 0 ? liveScale : savedScale
  readonly property bool active: moveArea.pressed || resizeArea.pressed

  width: holder.childrenRect.width
  height: holder.childrenRect.height
  x: centerX * area.width + dragOffset.x - width / 2
  y: centerY * area.height + dragOffset.y - height / 2
  scale: cardScale
  z: active ? 1 : 0

  function snap(value, step) { return Math.round(value / step) * step }

  function commit() {
    var cx = (centerX * area.width + dragOffset.x) / area.width
    var cy = (centerY * area.height + dragOffset.y) / area.height
    // Half-percent grid, with a pull towards the vertical centre line.
    cx = Math.abs(cx - 0.5) < 0.012 ? 0.5 : snap(cx, 0.005)
    cy = snap(cy, 0.005)
    var s = Math.max(0.4, Math.min(2.5, snap(cardScale, 0.05)))
    store.saveCard(key, { x: cx, y: cy, scale: s })
    dragOffset = Qt.point(0, 0)
    liveScale = -1
  }

  Item {
    id: holder
  }

  Rectangle {
    anchors.fill: parent
    anchors.margins: -Math.round(4 / slot.cardScale)
    visible: slot.editing
    color: "transparent"
    radius: Math.round(slot.height * 0.12)
    border.width: Math.max(1, Math.round(2 / slot.cardScale))
    border.color: Commons.Util.alpha(slot.accent, slot.active || moveArea.containsMouse ? 0.9 : 0.45)
  }

  MouseArea {
    id: moveArea
    anchors.fill: parent
    // Hidden, not just disabled, outside edit mode: a disabled MouseArea
    // still sets the cursor for everything under it.
    visible: slot.editing
    enabled: slot.editing
    hoverEnabled: true
    cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
    property point start

    onPressed: function(mouse) { start = mapToItem(slot.area, mouse.x, mouse.y) }
    onPositionChanged: function(mouse) {
      if (!pressed) return
      var p = mapToItem(slot.area, mouse.x, mouse.y)
      slot.dragOffset = Qt.point(p.x - start.x, p.y - start.y)
    }
    onReleased: slot.commit()
    onDoubleClicked: {
      slot.dragOffset = Qt.point(0, 0)
      slot.store.resetCard(slot.key)
    }
  }

  Rectangle {
    visible: slot.editing
    width: Math.round(18 / slot.cardScale)
    height: width
    radius: width / 2
    x: slot.width - width * 0.75
    y: slot.height - height * 0.75
    color: slot.accent
    border.width: Math.max(1, Math.round(2 / slot.cardScale))
    border.color: Commons.Color.background

    MouseArea {
      id: resizeArea
      anchors.fill: parent
      anchors.margins: -Math.round(8 / slot.cardScale)
      enabled: slot.editing
      cursorShape: Qt.SizeFDiagCursor
      property real startDistance: 1
      property real startScale: 1

      function distance(mouse) {
        var p = mapToItem(slot.area, mouse.x, mouse.y)
        var cx = slot.centerX * slot.area.width
        var cy = slot.centerY * slot.area.height
        return Math.max(1, Math.sqrt((p.x - cx) * (p.x - cx) + (p.y - cy) * (p.y - cy)))
      }

      onPressed: function(mouse) {
        startDistance = distance(mouse)
        startScale = slot.cardScale
      }
      onPositionChanged: function(mouse) {
        if (pressed) slot.liveScale = Math.max(0.4, Math.min(2.5, startScale * distance(mouse) / startDistance))
      }
      onReleased: slot.commit()
    }
  }
}

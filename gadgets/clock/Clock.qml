import QtQuick
import Quickshell
import qs.Commons as Commons
import "../../kit"

// Clock gadget: large time with the full date beneath it.
GlassCard {
  id: gadget

  // ---- gadget contract (see GadgetsWindow.qml)
  property var host: null
  readonly property real u: host ? host.u : 10
  readonly property real defaultX: 0.5
  readonly property real defaultY: 0.37
  property Item clickArea: null

  readonly property color fg: Commons.Color.foreground
  readonly property string fontFamily: Commons.Style.font.family
  readonly property var locale: Qt.locale("en_US")

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
  }

  unit: u
  width: Math.round(u * 76)
  height: timeColumn.height + Math.round(u * 7)

  Column {
    id: timeColumn
    anchors.centerIn: parent

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: Qt.formatTime(clock.date, "HH:mm")
      color: gadget.fg
      font.family: gadget.fontFamily
      font.pixelSize: Math.round(gadget.u * 17)
      font.letterSpacing: -Math.round(gadget.u * 17) * 0.04
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: gadget.locale.toString(clock.date, "dddd, MMMM d")
      color: Commons.Util.alpha(gadget.fg, 0.85)
      font.family: gadget.fontFamily
      font.pixelSize: Math.round(gadget.u * 2.2)
      font.letterSpacing: Math.round(gadget.u * 2.2) * 0.25
    }
  }
}

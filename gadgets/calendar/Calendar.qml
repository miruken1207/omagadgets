import QtQuick
import Quickshell
import qs.Commons as Commons
import "../../kit"
import "CalendarModel.js" as Model

// Calendar gadget: the current month, paged with ‹ ›; back to this month
// when the card leaves the screen.
GlassCard {
  id: gadget

  // ---- gadget contract (see GadgetsWindow.qml)
  property var host: null
  readonly property real u: host ? host.u : 10
  readonly property bool active: !!host && host.active
  readonly property bool editing: !!host && host.editing
  readonly property real defaultX: 0.84
  readonly property real defaultY: 0.3
  property Item clickArea: calendarHeader

  readonly property color fg: Commons.Color.foreground
  readonly property color bg: Commons.Color.background
  readonly property color accent: Commons.Color.accent
  readonly property string fontFamily: Commons.Style.font.family
  readonly property var locale: Qt.locale("en_US")

  readonly property real pad: Math.round(u * 2.6)

  function glyph(code) { return String.fromCodePoint(code) }

  // ---- data
  SystemClock {
    id: clock
    precision: SystemClock.Minutes
  }

  property int monthOffset: 0
  onActiveChanged: if (!active) monthOffset = 0

  readonly property var shownMonth: Model.shiftedMonth(clock.date, monthOffset)
  readonly property var monthCells: Model.monthCells(shownMonth, clock.date)

  // ---- card
  unit: u
  width: Math.round(u * 36)
  height: calendarColumn.height + 2 * pad

  Column {
    id: calendarColumn
    x: gadget.pad
    y: gadget.pad
    width: parent.width - 2 * gadget.pad
    spacing: Math.round(gadget.u * 1.2)

    Item {
      id: calendarHeader
      width: parent.width
      height: Math.round(gadget.u * 3)

      // Month title; a click returns to this month.
      Text {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: gadget.locale.toString(gadget.shownMonth, "MMMM yyyy")
        color: gadget.monthOffset === 0 ? gadget.fg : gadget.accent
        font.family: gadget.fontFamily
        font.pixelSize: Math.round(gadget.u * 1.8)

        MouseArea {
          anchors.fill: parent
          enabled: !gadget.editing && gadget.monthOffset !== 0
          onClicked: gadget.monthOffset = 0
        }
      }

      Row {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Math.round(gadget.u * 0.4)

        Repeater {
          model: [
            { step: -1, icon: 0xF0141 },  // chevron left
            { step: 1, icon: 0xF0142 }    // chevron right
          ]

          Rectangle {
            required property var modelData
            width: Math.round(gadget.u * 3)
            height: width
            radius: width / 2
            color: Commons.Util.alpha(gadget.fg, pageArea.containsMouse ? 0.14 : 0)

            Text {
              anchors.centerIn: parent
              text: gadget.glyph(modelData.icon)
              color: Commons.Util.alpha(gadget.fg, 0.75)
              font.family: gadget.fontFamily
              font.pixelSize: Math.round(gadget.u * 2)
            }

            MouseArea {
              id: pageArea
              anchors.fill: parent
              enabled: !gadget.editing
              hoverEnabled: true
              onClicked: gadget.monthOffset += modelData.step
            }
          }
        }
      }
    }

    Grid {
      id: monthGrid
      columns: 7
      readonly property real cell: Math.floor(calendarColumn.width / 7)

      Repeater {
        model: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        Text {
          required property string modelData
          width: monthGrid.cell
          height: Math.round(gadget.u * 2.6)
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          text: modelData
          color: Commons.Util.alpha(gadget.fg, 0.5)
          font.family: gadget.fontFamily
          font.pixelSize: Math.round(gadget.u * 1.2)
        }
      }

      Repeater {
        model: gadget.monthCells
        Item {
          required property var modelData
          width: monthGrid.cell
          height: Math.round(gadget.u * 3.4)

          Rectangle {
            visible: modelData.today
            anchors.centerIn: parent
            width: Math.round(gadget.u * 3)
            height: width
            radius: width / 2
            color: gadget.accent
          }

          Text {
            anchors.centerIn: parent
            visible: modelData.day > 0
            text: modelData.day
            color: modelData.today ? gadget.bg : Commons.Util.alpha(gadget.fg, 0.85)
            font.family: gadget.fontFamily
            font.pixelSize: Math.round(gadget.u * 1.35)
            font.bold: modelData.today
          }
        }
      }
    }
  }
}

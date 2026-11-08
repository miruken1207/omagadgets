import QtQuick
import qs.Commons as Commons

// Hint and Done button shown at the top of the screen in edit mode.
GlassCard {
  id: banner

  property real u: 10
  signal done()

  unit: u * 0.5
  width: bannerRow.width + Math.round(u * 3)
  height: bannerRow.height + Math.round(u * 1.8)

  Row {
    id: bannerRow
    anchors.centerIn: parent
    spacing: Math.round(banner.u * 2)

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: "Drag to move  ·  corner to resize  ·  double-click to reset"
      color: Commons.Util.alpha(Commons.Color.foreground, 0.85)
      font.family: Commons.Style.font.family
      font.pixelSize: Math.round(banner.u * 1.35)
    }

    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      width: doneLabel.width + Math.round(banner.u * 2.4)
      height: doneLabel.height + Math.round(banner.u * 0.9)
      radius: height / 2
      color: doneArea.containsMouse ? Commons.Color.accent : Commons.Util.alpha(Commons.Color.accent, 0.75)

      Text {
        id: doneLabel
        anchors.centerIn: parent
        text: "Done"
        color: Commons.Color.background
        font.family: Commons.Style.font.family
        font.pixelSize: Math.round(banner.u * 1.35)
        font.bold: true
      }

      MouseArea {
        id: doneArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: banner.done()
      }
    }
  }
}

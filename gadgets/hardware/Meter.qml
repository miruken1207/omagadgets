import QtQuick
import qs.Commons as Commons

// Icon, a thin meter and the value: one row of the hardware card.
Item {
  id: meter

  property real unit: 10
  property string icon: ""
  property string label: ""
  property real fraction: 0
  property string value: ""
  property string detail: ""

  readonly property color fg: Commons.Color.foreground
  readonly property color accent: Commons.Color.accent
  readonly property string fontFamily: Commons.Style.font.family

  height: Math.round(unit * 2.6)

  Row {
    id: meterIcon
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    width: Math.round(meter.unit * 7.5)
    spacing: Math.round(meter.unit * 0.7)
    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: meter.icon
      color: meter.accent
      font.family: meter.fontFamily
      font.pixelSize: Math.round(meter.unit * 1.8)
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: meter.label
      color: Commons.Util.alpha(meter.fg, 0.75)
      font.family: meter.fontFamily
      font.pixelSize: Math.round(meter.unit * 1.35)
    }
  }

  Text {
    id: meterValue
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    width: Math.round(meter.unit * 5.2)
    horizontalAlignment: Text.AlignRight
    text: meter.value
    color: Commons.Util.alpha(meter.fg, 0.9)
    font.family: meter.fontFamily
    font.pixelSize: Math.round(meter.unit * 1.45)
  }

  Text {
    id: meterDetail
    anchors.right: meterValue.left
    anchors.verticalCenter: parent.verticalCenter
    width: Math.round(meter.unit * 10.5)
    horizontalAlignment: Text.AlignRight
    text: meter.detail
    color: Commons.Util.alpha(meter.fg, 0.6)
    font.family: meter.fontFamily
    font.pixelSize: Math.round(meter.unit * 1.3)
  }

  Rectangle {
    anchors.left: meterIcon.right
    anchors.right: meterDetail.left
    anchors.rightMargin: Math.round(meter.unit * 1.2)
    anchors.verticalCenter: parent.verticalCenter
    height: Math.max(3, Math.round(meter.unit * 0.4))
    radius: height / 2
    color: Commons.Util.alpha(meter.fg, 0.12)

    Rectangle {
      width: parent.width * Math.max(0, Math.min(1, meter.fraction))
      height: parent.height
      radius: parent.radius
      color: meter.accent
      Behavior on width { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
    }
  }
}

import QtQuick
import qs.Commons as Commons

// Glass card. The frosting itself is Hyprland's blur on the
// "miruken1207-omagadgets" layer (layer rule in looknfeel.lua); only pixels
// above its ignore_alpha get blurred, i.e. just the cards.
Rectangle {
  property real unit: 10

  radius: Math.round(unit * 3)
  color: Commons.Util.alpha(Commons.Color.background, 0.32)
  border.width: 1
  border.color: Commons.Util.alpha(Commons.Color.foreground, 0.16)

  // Soft sheen from the top edge, as light catching the glass.
  Rectangle {
    anchors.fill: parent
    anchors.margins: 1
    radius: parent.radius - 1
    gradient: Gradient {
      GradientStop { position: 0.0; color: Commons.Util.alpha(Commons.Color.foreground, 0.09) }
      GradientStop { position: 0.45; color: Commons.Util.alpha(Commons.Color.foreground, 0.0) }
    }
  }
}

import QtQuick
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.Commons as Commons
import "../../kit"

// Now playing gadget: the current MPRIS track with previous / play-pause /
// next buttons, over a live spectrum from cava.
GlassCard {
  id: gadget

  // ---- gadget contract (see GadgetsWindow.qml)
  property var host: null
  readonly property real u: host ? host.u : 10
  readonly property bool active: !!host && host.active
  readonly property bool editing: !!host && host.editing
  readonly property real defaultX: 0.5
  readonly property real defaultY: 0.83
  property Item clickArea: mediaControls

  readonly property color fg: Commons.Color.foreground
  readonly property color accent: Commons.Color.accent
  readonly property string fontFamily: Commons.Style.font.family

  function glyph(code) { return String.fromCodePoint(code) }

  // ---- audio spectrum from cava (raw ascii frames on stdout), running only
  // while the card is on screen
  readonly property int cavaBars: 36
  property var cavaLevels: []

  Process {
    id: cavaProc
    running: gadget.active
    command: {
      var lines = [
        "[general]", "framerate = 30", "bars = " + gadget.cavaBars, "autosens = 1",
        "[input]", "method = pipewire", "source = auto",
        "[output]", "method = raw", "raw_target = /dev/stdout", "data_format = ascii",
        "ascii_max_range = 100", "bar_delimiter = 59", "frame_delimiter = 10",
        "channels = mono", "mono_option = average",
        "[smoothing]", "noise_reduction = 0.77"
      ]
      return ["bash", "-c", "exec cava -p <(printf '%s\\n' " + lines.map(function(l) { return "'" + l + "'" }).join(" ") + ")"]
    }
    stdout: SplitParser {
      onRead: function(data) {
        var levels = String(data).split(";").filter(function(v) { return v !== "" }).map(Number)
        if (levels.length > 0) gadget.cavaLevels = levels
      }
    }
    onExited: {
      gadget.cavaLevels = []
      if (gadget.active) cavaRetry.restart()
    }
  }

  // cava can exit when the audio server restarts; try again a little later.
  Timer {
    id: cavaRetry
    interval: 5000
    onTriggered: if (gadget.active && !cavaProc.running) cavaProc.running = true
  }

  // ---- now playing: a playing MPRIS player if there is one, else the
  // first one with a track (so a paused track can be resumed)
  readonly property var player: {
    var players = Mpris.players ? Mpris.players.values : []
    var fallback = null
    for (var i = 0; i < players.length; i++) {
      if (!players[i].trackTitle) continue
      if (players[i].playbackState === MprisPlaybackState.Playing) return players[i]
      if (!fallback) fallback = players[i]
    }
    return fallback
  }
  readonly property bool playing: !!player && player.playbackState === MprisPlaybackState.Playing

  // ---- card
  unit: u
  width: Math.round(u * 56)
  height: Math.round(u * 19)

  // Bars mirrored around the middle line; silence leaves a row of small dots.
  Row {
    id: spectrum
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: Math.round(gadget.u * 2.4)
    height: Math.round(gadget.u * 8)
    spacing: Math.round(gadget.u * 0.45)

    readonly property real barWidth: (width - spacing * (gadget.cavaBars - 1)) / gadget.cavaBars

    Repeater {
      model: gadget.cavaBars

      Item {
        required property int index
        width: spectrum.barWidth
        height: spectrum.height

        Rectangle {
          readonly property real level: (gadget.cavaLevels[parent.index] || 0) / 100
          anchors.centerIn: parent
          width: parent.width
          height: Math.max(width, parent.height * level)
          radius: width / 2
          color: Commons.Util.alpha(gadget.accent, 0.55 + 0.45 * level)
        }
      }
    }
  }

  Item {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.margins: Math.round(gadget.u * 2.4)
    height: Math.round(gadget.u * 4.6)

    Column {
      anchors.left: parent.left
      anchors.right: mediaControls.left
      anchors.rightMargin: Math.round(gadget.u * 2)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Math.round(gadget.u * 0.3)

      Text {
        width: parent.width
        elide: Text.ElideRight
        text: gadget.player ? gadget.player.trackTitle : "Nothing playing"
        color: gadget.player ? gadget.fg : Commons.Util.alpha(gadget.fg, 0.55)
        font.family: gadget.fontFamily
        font.pixelSize: Math.round(gadget.u * 1.6)
      }
      Text {
        width: parent.width
        visible: !!gadget.player && !!gadget.player.trackArtist
        elide: Text.ElideRight
        text: gadget.player ? gadget.player.trackArtist || "" : ""
        color: Commons.Util.alpha(gadget.fg, 0.65)
        font.family: gadget.fontFamily
        font.pixelSize: Math.round(gadget.u * 1.3)
      }
    }

    Row {
      id: mediaControls
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Math.round(gadget.u * 0.6)
      opacity: gadget.player ? 1 : 0.35

      Repeater {
        model: [
          { action: "previous", icon: 0xF04AE, big: false },
          { action: "toggle", icon: gadget.playing ? 0xF03E4 : 0xF040A, big: true },
          { action: "next", icon: 0xF04AD, big: false }
        ]

        Rectangle {
          required property var modelData
          width: Math.round(gadget.u * (modelData.big ? 4.6 : 3.8))
          height: width
          radius: width / 2
          color: modelData.big ? Commons.Util.alpha(gadget.accent, buttonArea.containsMouse ? 0.35 : 0.2)
            : Commons.Util.alpha(gadget.fg, buttonArea.containsMouse ? 0.14 : 0)

          Text {
            anchors.centerIn: parent
            text: gadget.glyph(modelData.icon)
            color: gadget.fg
            font.family: gadget.fontFamily
            font.pixelSize: Math.round(gadget.u * (modelData.big ? 2.6 : 2.2))
          }

          MouseArea {
            id: buttonArea
            anchors.fill: parent
            enabled: !!gadget.player && !gadget.editing
            hoverEnabled: true
            onClicked: {
              if (modelData.action === "previous") gadget.player.previous()
              else if (modelData.action === "next") gadget.player.next()
              else gadget.player.togglePlaying()
            }
          }
        }
      }
    }
  }
}

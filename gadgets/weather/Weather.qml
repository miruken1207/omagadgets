import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons as Commons
import "../../kit"
import "WeatherModel.js" as Model

// Weather gadget: current conditions and a three-day forecast from
// Open-Meteo, for the location set in Omarchy's weather settings.
GlassCard {
  id: gadget

  // ---- gadget contract (see GadgetsWindow.qml)
  property var host: null
  readonly property real u: host ? host.u : 10
  readonly property bool active: !!host && host.active
  readonly property real defaultX: 0.36
  readonly property real defaultY: 0.63
  property Item clickArea: null

  readonly property color fg: Commons.Color.foreground
  readonly property color accent: Commons.Color.accent
  readonly property string fontFamily: Commons.Style.font.family
  readonly property var locale: Qt.locale("en_US")

  readonly property real pad: Math.round(u * 2.6)
  readonly property real currentWidth: Math.round(u * 31)
  readonly property real forecastWidth: Math.round(u * 22.5)

  // ---- data (same location file as the bar's weather widget)
  property var location: null
  property var weather: null
  property real lastFetch: 0

  FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/settings/weather.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var data = JSON.parse(text())
        var lat = parseFloat(data.latitude)
        var lon = parseFloat(data.longitude)
        gadget.location = isNaN(lat) || isNaN(lon) ? null : { latitude: lat, longitude: lon }
      } catch (e) {
        gadget.location = null
      }
      gadget.lastFetch = 0
      gadget.fetch()
    }
  }

  function fetch() {
    if (!gadget.location || weatherProc.running) return
    weatherProc.command = ["curl", "-fsS", "--max-time", "8", Model.forecastUrl(gadget.location)]
    weatherProc.running = true
  }

  Process {
    id: weatherProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var next = Model.parseForecast(text, function(date) { return gadget.locale.toString(date, "ddd") })
        // Keep the last good reading on a failed request.
        if (!next) return
        gadget.weather = next
        gadget.lastFetch = Date.now()
      }
    }
  }

  // Refresh at most every 15 minutes, and straight away on coming back
  // after that long.
  Timer {
    interval: 60 * 1000
    repeat: true
    triggeredOnStart: true
    running: gadget.active
    onTriggered: if (Date.now() - gadget.lastFetch > 15 * 60 * 1000) gadget.fetch()
  }

  // ---- card
  unit: u
  width: currentWidth + forecastWidth
  height: Math.round(u * 18.5)

  Text {
    anchors.centerIn: parent
    visible: !gadget.weather
    text: "loading weather…"
    color: Commons.Util.alpha(gadget.fg, 0.6)
    font.family: gadget.fontFamily
    font.pixelSize: Math.round(gadget.u * 1.5)
  }

  Column {
    visible: !!gadget.weather
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: gadget.pad
    width: gadget.currentWidth - 2 * gadget.pad
    spacing: Math.round(gadget.u * 1.6)

    Row {
      spacing: Math.round(gadget.u * 1.6)
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: gadget.weather ? Model.icon(gadget.weather.code, gadget.weather.day) : ""
        color: gadget.accent
        font.family: gadget.fontFamily
        font.pixelSize: Math.round(gadget.u * 6.2)
      }
      Column {
        anchors.verticalCenter: parent.verticalCenter
        Text {
          text: gadget.weather ? Model.signed(gadget.weather.temperature) : ""
          color: gadget.fg
          font.family: gadget.fontFamily
          font.pixelSize: Math.round(gadget.u * 5)
        }
        Text {
          text: gadget.weather ? Model.describe(gadget.weather.code) : ""
          color: Commons.Util.alpha(gadget.fg, 0.8)
          font.family: gadget.fontFamily
          font.pixelSize: Math.round(gadget.u * 1.5)
        }
      }
    }

    Row {
      spacing: Math.round(gadget.u * 2.2)
      Repeater {
        model: gadget.weather ? [
          { icon: 0xF050F, text: "feels " + Model.signed(gadget.weather.feelsLike) },
          { icon: 0xF059D, text: Math.round(gadget.weather.wind) + " m/s" },
          { icon: 0xF058E, text: Math.round(gadget.weather.humidity) + "%" }
        ] : []
        Row {
          required property var modelData
          spacing: Math.round(gadget.u * 0.6)
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Model.glyph(modelData.icon)
            color: gadget.accent
            font.family: gadget.fontFamily
            font.pixelSize: Math.round(gadget.u * 1.6)
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: modelData.text
            color: Commons.Util.alpha(gadget.fg, 0.75)
            font.family: gadget.fontFamily
            font.pixelSize: Math.round(gadget.u * 1.3)
          }
        }
      }
    }
  }

  // ---- three-day forecast
  Rectangle {
    visible: !!gadget.weather
    x: gadget.currentWidth
    anchors.verticalCenter: parent.verticalCenter
    width: 1
    height: parent.height - 2 * gadget.pad
    color: Commons.Util.alpha(gadget.fg, 0.14)
  }

  Column {
    visible: !!gadget.weather
    x: gadget.currentWidth + Math.round(gadget.u * 2.2)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Math.round(gadget.u * 1.5)

    Repeater {
      model: gadget.weather ? gadget.weather.forecast : []

      Row {
        required property var modelData
        spacing: Math.round(gadget.u * 1)

        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: Math.round(gadget.u * 4)
          text: modelData.day
          color: Commons.Util.alpha(gadget.fg, 0.75)
          font.family: gadget.fontFamily
          font.pixelSize: Math.round(gadget.u * 1.4)
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: Math.round(gadget.u * 2.8)
          horizontalAlignment: Text.AlignHCenter
          text: Model.icon(modelData.code, true)
          color: gadget.accent
          font.family: gadget.fontFamily
          font.pixelSize: Math.round(gadget.u * 2.2)
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: Math.round(gadget.u * 3.6)
          horizontalAlignment: Text.AlignRight
          text: Model.signed(modelData.max)
          color: gadget.fg
          font.family: gadget.fontFamily
          font.pixelSize: Math.round(gadget.u * 1.45)
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          width: Math.round(gadget.u * 3.6)
          horizontalAlignment: Text.AlignRight
          text: Model.signed(modelData.min)
          color: Commons.Util.alpha(gadget.fg, 0.55)
          font.family: gadget.fontFamily
          font.pixelSize: Math.round(gadget.u * 1.45)
        }
      }
    }
  }
}

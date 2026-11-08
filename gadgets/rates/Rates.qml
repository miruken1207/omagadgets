import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons as Commons
import "../../kit"
import "RatesModel.js" as Model

// Rates gadget: fiat and crypto prices in one of a few currencies picked by
// tabs. Fiat from the Central Bank of Uzbekistan (refreshed every 3 hours),
// crypto from CoinGecko (every 5 minutes), only while on screen. The last
// answers are cached so the card fills in at once after a shell restart.
GlassCard {
  id: gadget

  // ---- gadget contract (see GadgetsWindow.qml)
  property var host: null
  readonly property real u: host ? host.u : 10
  readonly property bool active: !!host && host.active
  readonly property bool editing: !!host && host.editing
  readonly property real defaultX: 0.16
  readonly property real defaultY: 0.32
  property Item clickArea: tabsRow

  readonly property var cfg: Model.resolveOptions(host ? host.options : null)

  readonly property color fg: Commons.Color.foreground
  readonly property color accent: Commons.Color.accent
  readonly property string fontFamily: Commons.Style.font.family
  readonly property real pad: Math.round(u * 2.6)

  readonly property string home: Quickshell.env("HOME")
  readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || home + "/.cache") + "/omagadgets"
  readonly property string stateDir: home + "/.local/state/omagadgets"

  // ---- theme colours for rising / falling, from the theme's palette
  property color upColor: accent
  property color downColor: Commons.Color.urgent

  FileView {
    path: Commons.Color.currentThemePath + "/colors.toml"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var raw = text()
      var green = /^green\s*=\s*"(#[0-9a-fA-F]{6,8})"/m.exec(raw)
      var red = /^red\s*=\s*"(#[0-9a-fA-F]{6,8})"/m.exec(raw)
      gadget.upColor = green ? green[1] : gadget.accent
      gadget.downColor = red ? red[1] : Commons.Color.urgent
    }
  }

  // ---- selected tab, remembered across restarts
  property string savedBase: ""
  readonly property string base: cfg.tabs.indexOf(savedBase) !== -1 ? savedBase : cfg.tabs[0]

  FileView {
    id: baseFile
    path: gadget.stateDir + "/rates-base"
    printErrors: false
    onLoaded: gadget.savedBase = text().trim()
  }

  function selectBase(code) {
    gadget.savedBase = code
    baseFile.setText(code + "\n")
  }

  // ---- data
  property var cbu: null
  property real cbuFetched: 0
  property var crypto: null
  property real cryptoFetched: 0

  readonly property var rows: Model.rows(cfg.assets, base, cbu, crypto)

  // Cache and state files live in directories that may not exist yet.
  Process {
    running: true
    command: ["mkdir", "-p", gadget.cacheDir, gadget.stateDir]
  }

  FileView {
    id: cacheFile
    path: gadget.cacheDir + "/rates.json"
    printErrors: false
    onLoaded: {
      try {
        var data = JSON.parse(text())
        if (data.cbu && !gadget.cbu) { gadget.cbu = data.cbu; gadget.cbuFetched = data.cbuFetched || 0 }
        if (data.crypto && !gadget.crypto) { gadget.crypto = data.crypto; gadget.cryptoFetched = data.cryptoFetched || 0 }
      } catch (e) {
        // No usable cache: wait for the first fetch.
      }
    }
  }

  function saveCache() {
    cacheFile.setText(JSON.stringify({
      cbu: gadget.cbu, cbuFetched: gadget.cbuFetched,
      crypto: gadget.crypto, cryptoFetched: gadget.cryptoFetched
    }) + "\n")
  }

  Process {
    id: cbuProc
    command: ["curl", "-fsS", "--max-time", "10", Model.CBU_URL]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var next = Model.parseCbu(text)
        // Keep the last good reading on a failed request.
        if (!next) return
        gadget.cbu = next
        gadget.cbuFetched = Date.now()
        gadget.saveCache()
      }
    }
  }

  Process {
    id: cryptoProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var next = Model.parseCoingecko(text)
        if (!next) return
        gadget.crypto = next
        gadget.cryptoFetched = Date.now()
        gadget.saveCache()
      }
    }
  }

  function refresh() {
    var now = Date.now()
    if (now - gadget.cbuFetched > 3 * 3600 * 1000 && !cbuProc.running)
      cbuProc.running = true
    var url = Model.coingeckoUrl(gadget.cfg.assets, gadget.cfg.tabs)
    if (url && now - gadget.cryptoFetched > 5 * 60 * 1000 && !cryptoProc.running) {
      cryptoProc.command = ["curl", "-fsS", "--max-time", "10", url]
      cryptoProc.running = true
    }
  }

  // Check every minute while on screen; each source refetches once stale.
  Timer {
    interval: 60 * 1000
    repeat: true
    triggeredOnStart: true
    running: gadget.active
    onTriggered: gadget.refresh()
  }

  // A newly listed coin or tab should not wait for the cache to go stale.
  // Compared by value: cfg is rebuilt on every shell.json save.
  readonly property string cfgKey: JSON.stringify(cfg)
  property string fetchedKey: ""
  onCfgKeyChanged: {
    if (gadget.fetchedKey !== "" && gadget.fetchedKey !== gadget.cfgKey) {
      gadget.cryptoFetched = 0
      if (gadget.active) gadget.refresh()
    }
    gadget.fetchedKey = gadget.cfgKey
  }

  // "CBU 07.11 · crypto 22:45"
  readonly property string updatedText: {
    var parts = []
    if (cbu && cbu.date) parts.push("CBU " + cbu.date.slice(0, 5))
    if (crypto && cryptoFetched > 0) parts.push("crypto " + Qt.formatTime(new Date(cryptoFetched), "HH:mm"))
    return parts.join("  ·  ")
  }

  // ---- card
  unit: u
  width: Math.round(u * 40)
  height: column.height + 2 * pad

  Column {
    id: column
    x: gadget.pad
    y: gadget.pad
    width: parent.width - 2 * gadget.pad
    spacing: Math.round(gadget.u * 1.2)

    // Base currency tabs; the selected one is outlined.
    Row {
      id: tabsRow
      spacing: Math.round(gadget.u * 0.8)

      Repeater {
        model: gadget.cfg.tabs

        Rectangle {
          required property string modelData
          readonly property bool selected: modelData === gadget.base
          width: tabLabel.width + Math.round(gadget.u * 2.4)
          height: Math.round(gadget.u * 3.4)
          radius: Math.round(height * 0.3)
          color: Commons.Util.alpha(gadget.fg, tabArea.containsMouse && !selected ? 0.08 : 0)
          border.width: selected ? Math.max(1, Math.round(gadget.u * 0.12)) : 0
          border.color: Commons.Util.alpha(gadget.accent, 0.8)

          Text {
            id: tabLabel
            anchors.centerIn: parent
            text: parent.modelData
            color: parent.selected ? gadget.fg : Commons.Util.alpha(gadget.fg, 0.6)
            font.family: gadget.fontFamily
            font.pixelSize: Math.round(gadget.u * 1.6)
            font.bold: parent.selected
          }

          MouseArea {
            id: tabArea
            anchors.fill: parent
            enabled: !gadget.editing
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: gadget.selectBase(parent.modelData)
          }
        }
      }
    }

    Rectangle {
      width: parent.width
      height: 1
      color: Commons.Util.alpha(gadget.fg, 0.14)
    }

    Text {
      visible: !gadget.cbu && !gadget.crypto
      text: "loading rates…"
      color: Commons.Util.alpha(gadget.fg, 0.6)
      font.family: gadget.fontFamily
      font.pixelSize: Math.round(gadget.u * 1.4)
    }

    // "1 USD      11 987 UZS  ▲0.11%"
    Repeater {
      model: (gadget.cbu || gadget.crypto) ? gadget.rows : []

      Item {
        required property var modelData
        width: column.width
        height: Math.round(gadget.u * 3)

        Text {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: modelData.amount + " " + modelData.asset
          color: Commons.Util.alpha(gadget.fg, 0.75)
          font.family: gadget.fontFamily
          font.pixelSize: Math.round(gadget.u * 1.5)
        }

        Text {
          id: changeText
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: Math.round(gadget.u * 7.6)
          horizontalAlignment: Text.AlignRight
          text: modelData.change.text
          color: modelData.change.direction > 0 ? gadget.upColor
            : modelData.change.direction < 0 ? gadget.downColor
            : Commons.Util.alpha(gadget.fg, 0.5)
          font.family: gadget.fontFamily
          font.pixelSize: Math.round(gadget.u * 1.25)
        }

        Text {
          id: baseText
          anchors.right: changeText.left
          anchors.rightMargin: Math.round(gadget.u * 1)
          anchors.baseline: valueText.baseline
          text: gadget.base
          color: Commons.Util.alpha(gadget.fg, 0.5)
          font.family: gadget.fontFamily
          font.pixelSize: Math.round(gadget.u * 1.2)
        }

        Text {
          id: valueText
          anchors.right: baseText.left
          anchors.rightMargin: Math.round(gadget.u * 0.6)
          anchors.verticalCenter: parent.verticalCenter
          text: modelData.value
          color: gadget.fg
          font.family: gadget.fontFamily
          font.pixelSize: Math.round(gadget.u * 1.6)
        }
      }
    }

    Text {
      visible: gadget.updatedText !== ""
      text: gadget.updatedText
      color: Commons.Util.alpha(gadget.fg, 0.45)
      font.family: gadget.fontFamily
      font.pixelSize: Math.round(gadget.u * 1.15)
    }
  }
}

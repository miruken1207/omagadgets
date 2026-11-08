import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import qs.Commons as Commons

// omagadgets: glass desktop cards (clock, weather, hardware, now playing,
// calendar) that can be dragged and resized in edit mode. Drawn on the Bottom
// layer (above the wallpaper, under windows) and only while the "home"
// workspace is active on that monitor.
Item {
  id: root

  // ---- injected by the shell
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null
  property var pluginRegistry: null

  readonly property string workspaceName: "home"
  readonly property string home: Quickshell.env("HOME")
  readonly property var locale: Qt.locale("en_US")

  readonly property color fg: Commons.Color.foreground
  readonly property color bg: Commons.Color.background
  readonly property color accent: Commons.Color.accent
  readonly property string fontFamily: Commons.Style.font.family

  // True while any monitor shows home; polling and requests pause otherwise.
  readonly property bool anyShown: {
    var monitors = Hyprland.monitors.values
    for (var i = 0; i < monitors.length; i++) {
      var ws = monitors[i].activeWorkspace
      if (ws && ws.name === root.workspaceName) return true
    }
    return false
  }

  function glyph(code) { return String.fromCodePoint(code) }
  function signed(t) { t = Math.round(t); return (t > 0 ? "+" : "") + t + "°" }

  // ---- clock
  SystemClock {
    id: clock
    precision: SystemClock.Minutes
  }

  // ---- weather (Open-Meteo, same location file as the bar's weather widget)
  property var location: null
  property var weather: null
  property real lastWeatherFetch: 0

  FileView {
    path: root.home + "/.local/state/omarchy/settings/weather.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var data = JSON.parse(text())
        var lat = parseFloat(data.latitude)
        var lon = parseFloat(data.longitude)
        root.location = isNaN(lat) || isNaN(lon) ? null : { latitude: lat, longitude: lon }
      } catch (e) {
        root.location = null
      }
      root.lastWeatherFetch = 0
      root.fetchWeather()
    }
  }

  function fetchWeather() {
    if (!root.location || weatherProc.running) return
    var url = "https://api.open-meteo.com/v1/forecast"
      + "?latitude=" + root.location.latitude
      + "&longitude=" + root.location.longitude
      + "&current=temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,weather_code,is_day"
      + "&daily=weather_code,temperature_2m_max,temperature_2m_min&forecast_days=4"
      + "&wind_speed_unit=ms&timezone=auto"
    weatherProc.command = ["curl", "-fsS", "--max-time", "8", url]
    weatherProc.running = true
  }

  Process {
    id: weatherProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var data = JSON.parse(String(text || ""))
          var c = data.current
          var d = data.daily
          // The next three days; index 0 is today.
          var forecast = []
          for (var i = 1; i < 4 && d && i < d.time.length; i++)
            forecast.push({
              day: root.locale.toString(new Date(d.time[i] + "T12:00:00"), "ddd"),
              code: d.weather_code[i],
              max: d.temperature_2m_max[i],
              min: d.temperature_2m_min[i]
            })
          root.weather = {
            forecast: forecast,
            temperature: c.temperature_2m,
            feelsLike: c.apparent_temperature,
            humidity: c.relative_humidity_2m,
            wind: c.wind_speed_10m,
            code: c.weather_code,
            day: c.is_day === 1
          }
          root.lastWeatherFetch = Date.now()
        } catch (e) {
          // Keep the last good reading.
        }
      }
    }
  }

  // Refresh at most every 15 minutes, and straight away on returning home
  // after that long.
  Timer {
    interval: 60 * 1000
    repeat: true
    triggeredOnStart: true
    running: root.anyShown
    onTriggered: if (Date.now() - root.lastWeatherFetch > 15 * 60 * 1000) root.fetchWeather()
  }

  function weatherIcon(code, day) {
    if (code === 0 || code === 1) return glyph(day ? 0xF0599 : 0xF0594)  // sunny / night
    if (code === 2) return glyph(day ? 0xF0595 : 0xF0F31)                // partly cloudy
    if (code === 3) return glyph(0xF0590)                                // cloudy
    if (code === 45 || code === 48) return glyph(0xF0591)                // fog
    if (code >= 51 && code <= 67) return glyph(0xF0597)                  // rain
    if (code >= 71 && code <= 77) return glyph(0xF0598)                  // snow
    if (code >= 80 && code <= 82) return glyph(0xF0596)                  // pouring
    if (code === 85 || code === 86) return glyph(0xF0598)
    if (code >= 95) return glyph(0xF0593)                                // thunder
    return glyph(0xF0590)
  }

  function weatherText(code) {
    if (code === 0) return "clear"
    if (code === 1) return "mostly clear"
    if (code === 2) return "partly cloudy"
    if (code === 3) return "overcast"
    if (code === 45 || code === 48) return "fog"
    if (code >= 51 && code <= 57) return "drizzle"
    if (code >= 61 && code <= 67) return "rain"
    if (code >= 71 && code <= 77) return "snow"
    if (code >= 80 && code <= 82) return "showers"
    if (code === 85 || code === 86) return "snow showers"
    if (code >= 95) return "thunderstorm"
    return ""
  }

  // ---- hardware: CPU from /proc/stat deltas, memory from /proc/meminfo,
  // package temperature from coretemp, the NVIDIA card from nvidia-smi,
  // root filesystem from df
  property int cpuPercent: -1
  property int memPercent: -1
  property real memUsedGb: -1
  property real memTotalGb: -1
  property int cpuTemp: -1
  property var gpu: null
  property real diskUsedGb: -1
  property real diskTotalGb: -1

  // "7.1 / 31 GB": one decimal below 10 GB, whole numbers above.
  function gbPair(used, total) {
    function fmt(v) { return v < 10 ? v.toFixed(1) : String(Math.round(v)) }
    return used < 0 || total <= 0 ? "" : fmt(used) + " / " + fmt(total) + " GB"
  }
  property int diskPercent: -1
  property var lastCpu: null

  FileView {
    id: statFile
    path: "/proc/stat"
    onLoaded: {
      var parts = text().split("\n")[0].trim().split(/\s+/).slice(1).map(Number)
      var idle = parts[3] + (parts[4] || 0)
      var total = parts.reduce(function(a, b) { return a + b }, 0)
      if (root.lastCpu && total > root.lastCpu.total)
        root.cpuPercent = Math.round(100 * (1 - (idle - root.lastCpu.idle) / (total - root.lastCpu.total)))
      root.lastCpu = { idle: idle, total: total }
    }
  }

  FileView {
    id: memFile
    path: "/proc/meminfo"
    onLoaded: {
      var raw = text()
      var total = Number((/MemTotal:\s+(\d+)/.exec(raw) || [0, 0])[1])
      var avail = Number((/MemAvailable:\s+(\d+)/.exec(raw) || [0, 0])[1])
      if (total > 0) {
        root.memPercent = Math.round(100 * (1 - avail / total))
        root.memUsedGb = (total - avail) / 1048576
        root.memTotalGb = total / 1048576
      }
    }
  }

  // NVIDIA dGPU. nvidia-smi wakes a runtime-suspended card and drains the
  // battery, so it only runs while the card is already awake; a sleeping card
  // reads "sleep".
  Process {
    id: gpuProc
    command: ["sh", "-c",
      "d=$(ls -d /sys/bus/pci/drivers/nvidia/0000:* 2>/dev/null | head -n1); "
      + "[ -n \"$d\" ] || exit 0; "
      + "[ \"$(cat $d/power/runtime_status 2>/dev/null)\" = suspended ] && { echo sleep; exit 0; }; "
      + "nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu --format=csv,noheader,nounits"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        if (raw === "") {
          root.gpu = null
        } else if (raw === "sleep") {
          root.gpu = { asleep: true }
        } else {
          var parts = raw.split("\n")[0].split(",").map(function(p) { return Number(p.trim()) })
          if (parts.length === 4 && !parts.some(isNaN))
            root.gpu = {
              asleep: false,
              util: parts[0],
              memPercent: Math.round(100 * parts[1] / parts[2]),
              memUsedGb: parts[1] / 1024,
              memTotalGb: parts[2] / 1024,
              temp: parts[3]
            }
        }
      }
    }
  }

  // hwmon numbers move between boots, so find coretemp by name once.
  Process {
    running: true
    command: ["sh", "-c", "for h in /sys/class/hwmon/hwmon*; do [ \"$(cat $h/name)\" = coretemp ] && echo $h/temp1_input && break; done"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: tempFile.path = String(text || "").trim()
    }
  }

  FileView {
    id: tempFile
    printErrors: false
    onLoaded: root.cpuTemp = Math.round(Number(text()) / 1000)
  }

  Process {
    id: diskProc
    command: ["df", "-B1", "--output=used,size", "/"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parts = String(text || "").split("\n")[1].trim().split(/\s+/).map(Number)
        if (parts.length === 2 && parts[1] > 0) {
          root.diskUsedGb = parts[0] / 1073741824
          root.diskTotalGb = parts[1] / 1073741824
          root.diskPercent = Math.round(100 * parts[0] / parts[1])
        }
      }
    }
  }

  Timer {
    interval: 2000
    repeat: true
    triggeredOnStart: true
    running: root.anyShown
    property int ticks: 0
    onTriggered: {
      statFile.reload()
      memFile.reload()
      if (tempFile.path) tempFile.reload()
      if (!gpuProc.running) gpuProc.running = true
      if (ticks++ % 30 === 0 && !diskProc.running) diskProc.running = true
    }
  }

  // ---- building blocks

  // Glass card. The frosting itself is Hyprland's blur on the
  // "miruken1207-omagadgets" layer (layer rule in looknfeel.lua); only pixels above
  // its ignore_alpha get blurred, i.e. just the cards.
  component GlassCard: Rectangle {
    property real unit: 10
    radius: Math.round(unit * 3)
    color: Commons.Util.alpha(root.bg, 0.32)
    border.width: 1
    border.color: Commons.Util.alpha(root.fg, 0.16)

    // Soft sheen from the top edge, as light catching the glass.
    Rectangle {
      anchors.fill: parent
      anchors.margins: 1
      radius: parent.radius - 1
      gradient: Gradient {
        GradientStop { position: 0.0; color: Commons.Util.alpha(root.fg, 0.09) }
        GradientStop { position: 0.45; color: Commons.Util.alpha(root.fg, 0.0) }
      }
    }
  }

  // Icon, a thin meter and the value, for the hardware card.
  component Meter: Item {
    property real unit: 10
    property string icon: ""
    property string label: ""
    property real fraction: 0
    property string value: ""
    property string detail: ""
    height: Math.round(unit * 2.6)

    Row {
      id: meterIcon
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: Math.round(unit * 7.5)
      spacing: Math.round(unit * 0.7)
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: parent.parent.icon
        color: root.accent
        font.family: root.fontFamily
        font.pixelSize: Math.round(unit * 1.8)
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: parent.parent.label
        color: Commons.Util.alpha(root.fg, 0.75)
        font.family: root.fontFamily
        font.pixelSize: Math.round(unit * 1.35)
      }
    }

    Text {
      id: meterValue
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: Math.round(unit * 5.2)
      horizontalAlignment: Text.AlignRight
      text: parent.value
      color: Commons.Util.alpha(root.fg, 0.9)
      font.family: root.fontFamily
      font.pixelSize: Math.round(unit * 1.45)
    }

    Text {
      id: meterDetail
      anchors.right: meterValue.left
      anchors.verticalCenter: parent.verticalCenter
      width: Math.round(unit * 10.5)
      horizontalAlignment: Text.AlignRight
      text: parent.detail
      color: Commons.Util.alpha(root.fg, 0.6)
      font.family: root.fontFamily
      font.pixelSize: Math.round(unit * 1.3)
    }

    Rectangle {
      anchors.left: meterIcon.right
      anchors.right: meterDetail.left
      anchors.rightMargin: Math.round(unit * 1.2)
      anchors.verticalCenter: parent.verticalCenter
      height: Math.max(3, Math.round(unit * 0.4))
      radius: height / 2
      color: Commons.Util.alpha(root.fg, 0.12)

      Rectangle {
        width: parent.width * Math.max(0, Math.min(1, parent.parent.fraction))
        height: parent.height
        radius: parent.radius
        color: root.accent
        Behavior on width { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
      }
    }
  }

  // ---- audio spectrum from cava (raw ascii frames on stdout), running only
  // while home is on screen
  readonly property int cavaBars: 36
  property var cavaLevels: []

  Process {
    id: cavaProc
    running: root.anyShown
    command: {
      var lines = [
        "[general]", "framerate = 30", "bars = " + root.cavaBars, "autosens = 1",
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
        if (levels.length > 0) root.cavaLevels = levels
      }
    }
    onExited: {
      root.cavaLevels = []
      if (root.anyShown) cavaRetry.restart()
    }
  }

  // cava can exit when the audio server restarts; try again a little later.
  Timer {
    id: cavaRetry
    interval: 5000
    onTriggered: if (root.anyShown && !cavaProc.running) cavaProc.running = true
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

  // ---- calendar: the current month, paged with ‹ ›; back to this month
  // on leaving home
  property int monthOffset: 0
  onAnyShownChanged: if (!anyShown) monthOffset = 0

  readonly property var shownMonth: new Date(clock.date.getFullYear(), clock.date.getMonth() + root.monthOffset, 1)

  // The shown month as Monday-first weeks: { day (0 = padding), today }.
  readonly property var monthCells: {
    var y = root.shownMonth.getFullYear(), m = root.shownMonth.getMonth()
    var now = clock.date
    var current = now.getFullYear() === y && now.getMonth() === m
    var offset = (new Date(y, m, 1).getDay() + 6) % 7
    var days = new Date(y, m + 1, 0).getDate()
    var cells = []
    for (var i = 0; i < offset; i++) cells.push({ day: 0, today: false })
    for (var day = 1; day <= days; day++) cells.push({ day: day, today: current && day === now.getDate() })
    while (cells.length % 7 !== 0) cells.push({ day: 0, today: false })
    return cells
  }

  // ---- layout: each card's centre (fractions of the screen) and scale,
  // read from omagadgets.json; a card with no entry sits at its default.
  property var layout: ({})

  FileView {
    id: layoutFile
    path: root.home + "/.config/omarchy/omagadgets.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var data = JSON.parse(text())
        root.layout = data && typeof data === "object" ? data : ({})
      } catch (e) {
        root.layout = ({})
      }
    }
    onLoadFailed: root.layout = ({})
  }

  function writeLayout(next) {
    root.layout = next
    layoutFile.setText(JSON.stringify(next, null, 2) + "\n")
  }

  function saveCard(key, entry) {
    var next = Object.assign({}, root.layout)
    next[key] = entry
    writeLayout(next)
  }

  function resetCard(key) {
    var next = Object.assign({}, root.layout)
    delete next[key]
    writeLayout(next)
  }

  // Edit mode lives in a flag file so a keybinding can flip it with a plain
  // shell script (omagadgets-edit, shipped with the plugin), no IPC involved.
  property bool editing: false

  FileView {
    id: editFlag
    path: root.home + "/.local/state/omagadgets/editing"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.editing = text().trim() === "1"
    onLoadFailed: root.editing = false
  }

  function finishEditing() {
    root.editing = false
    editFlag.setText("0\n")
  }

  // A card placed by its centre and scaled around it. In edit mode it can be
  // dragged, scaled from the corner handle (proportionally, around its
  // centre) and put back to its default place and size with a double click.
  component CardSlot: Item {
    id: slot

    property string key: ""
    property Item area: null
    property real defaultX: 0.5
    property real defaultY: 0.5
    default property alias body: holder.data

    readonly property var saved: root.layout[key] || null
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
      root.saveCard(key, { x: cx, y: cy, scale: s })
      dragOffset = Qt.point(0, 0)
      liveScale = -1
    }

    Item {
      id: holder
    }

    Rectangle {
      anchors.fill: parent
      anchors.margins: -Math.round(4 / slot.cardScale)
      visible: root.editing
      color: "transparent"
      radius: Math.round(slot.height * 0.12)
      border.width: Math.max(1, Math.round(2 / slot.cardScale))
      border.color: Commons.Util.alpha(root.accent, slot.active || moveArea.containsMouse ? 0.9 : 0.45)
    }

    MouseArea {
      id: moveArea
      anchors.fill: parent
      // Hidden, not just disabled, outside edit mode: a disabled MouseArea
      // still sets the cursor for everything under it.
      visible: root.editing
      enabled: root.editing
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
        root.resetCard(slot.key)
      }
    }

    Rectangle {
      visible: root.editing
      width: Math.round(18 / slot.cardScale)
      height: width
      radius: width / 2
      x: slot.width - width * 0.75
      y: slot.height - height * 0.75
      color: root.accent
      border.width: Math.max(1, Math.round(2 / slot.cardScale))
      border.color: root.bg

      MouseArea {
        id: resizeArea
        anchors.fill: parent
        anchors.margins: -Math.round(8 / slot.cardScale)
        enabled: root.editing
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

  // ---- one surface per monitor
  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: surface

      required property var modelData
      screen: modelData

      readonly property var hyprMonitor: Hyprland.monitorFor(modelData)
      readonly property bool shown: !!(hyprMonitor && hyprMonitor.activeWorkspace
        && hyprMonitor.activeWorkspace.name === root.workspaceName)

      // Everything is sized in hundredths of the screen height.
      readonly property real u: height / 100

      anchors { top: true; bottom: true; left: true; right: true }
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.layer: WlrLayer.Bottom
      WlrLayershell.namespace: "miruken1207-omagadgets"
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      readonly property bool editing: root.editing && shown

      // Clicks fall through to the desktop except on the media buttons and
      // the calendar header, and everywhere while editing.
      property Region clickInput: Region {
        regions: [
          Region { item: mediaControls },
          Region { item: calendarHeader }
        ]
      }
      mask: editing ? null : clickInput
      visible: shown || content.opacity > 0

      Item {
        id: content
        anchors.fill: parent
        opacity: surface.shown ? 1 : 0
        scale: surface.shown ? 1 : 0.97
        Behavior on opacity { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }

        GlassCard {
          z: 2
          visible: surface.editing
          unit: surface.u * 0.5
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.top: parent.top
          anchors.topMargin: Math.round(surface.u * 5)
          width: bannerRow.width + Math.round(surface.u * 3)
          height: bannerRow.height + Math.round(surface.u * 1.8)

          Row {
            id: bannerRow
            anchors.centerIn: parent
            spacing: Math.round(surface.u * 2)

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "Drag to move  ·  corner to resize  ·  double-click to reset"
              color: Commons.Util.alpha(root.fg, 0.85)
              font.family: root.fontFamily
              font.pixelSize: Math.round(surface.u * 1.35)
            }

            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              width: doneLabel.width + Math.round(surface.u * 2.4)
              height: doneLabel.height + Math.round(surface.u * 0.9)
              radius: height / 2
              color: doneArea.containsMouse ? root.accent : Commons.Util.alpha(root.accent, 0.75)

              Text {
                id: doneLabel
                anchors.centerIn: parent
                text: "Done"
                color: root.bg
                font.family: root.fontFamily
                font.pixelSize: Math.round(surface.u * 1.35)
                font.bold: true
              }

              MouseArea {
                id: doneArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.finishEditing()
              }
            }
          }
        }

        Item {
          id: stack
          anchors.fill: parent

          readonly property real gap: Math.round(surface.u * 1.6)
          readonly property real cardWidth: Math.round(surface.u * 76)
          readonly property real pad: Math.round(surface.u * 2.6)
          readonly property real weatherWidth: Math.round(surface.u * 31)
          readonly property real forecastWidth: Math.round(surface.u * 22.5)
          readonly property real weatherCardWidth: weatherWidth + forecastWidth
          readonly property real hardwareWidth: cardWidth - gap - weatherWidth
          readonly property real cardHeight: Math.round(surface.u * 18.5)

          // Default layout: the time card on top, weather and hardware side by
          // side beneath it, the whole group centred a little above middle.
          readonly property real groupTop: (height - (timeCard.height + gap + cardHeight)) / 2 - surface.u * 3
          readonly property real lowerY: (groupTop + timeCard.height + gap + cardHeight / 2) / height
          readonly property real lowerLeft: (width - (weatherCardWidth + gap + hardwareWidth)) / 2

          CardSlot {
            key: "time"
            area: stack
            defaultX: 0.5
            defaultY: (stack.groupTop + timeCard.height / 2) / stack.height

            GlassCard {
              unit: surface.u
              id: timeCard
              width: stack.cardWidth
              height: timeColumn.height + Math.round(surface.u * 7)

              Column {
                id: timeColumn
                anchors.centerIn: parent

                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: Qt.formatTime(clock.date, "HH:mm")
                  color: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Math.round(surface.u * 17)
                  font.letterSpacing: -Math.round(surface.u * 17) * 0.04
                }

                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: root.locale.toString(clock.date, "dddd, MMMM d")
                  color: Commons.Util.alpha(root.fg, 0.85)
                  font.family: root.fontFamily
                  font.pixelSize: Math.round(surface.u * 2.2)
                  font.letterSpacing: Math.round(surface.u * 2.2) * 0.25
                }
              }
            }
          }

          CardSlot {
            key: "weather"
            area: stack
            defaultX: (stack.lowerLeft + stack.weatherCardWidth / 2) / stack.width
            defaultY: stack.lowerY

            GlassCard {
              unit: surface.u
              width: stack.weatherCardWidth
              height: stack.cardHeight

              Text {
                anchors.centerIn: parent
                visible: !root.weather
                text: "loading weather…"
                color: Commons.Util.alpha(root.fg, 0.6)
                font.family: root.fontFamily
                font.pixelSize: Math.round(surface.u * 1.5)
              }

              Column {
                visible: !!root.weather
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: stack.pad
                width: stack.weatherWidth - 2 * stack.pad
                spacing: Math.round(surface.u * 1.6)

                Row {
                  spacing: Math.round(surface.u * 1.6)
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.weather ? root.weatherIcon(root.weather.code, root.weather.day) : ""
                    color: root.accent
                    font.family: root.fontFamily
                    font.pixelSize: Math.round(surface.u * 6.2)
                  }
                  Column {
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                      text: root.weather ? root.signed(root.weather.temperature) : ""
                      color: root.fg
                      font.family: root.fontFamily
                      font.pixelSize: Math.round(surface.u * 5)
                    }
                    Text {
                      text: root.weather ? root.weatherText(root.weather.code) : ""
                      color: Commons.Util.alpha(root.fg, 0.8)
                      font.family: root.fontFamily
                      font.pixelSize: Math.round(surface.u * 1.5)
                    }
                  }
                }

                Row {
                  spacing: Math.round(surface.u * 2.2)
                  Repeater {
                    model: root.weather ? [
                      { icon: 0xF050F, text: "feels " + root.signed(root.weather.feelsLike) },
                      { icon: 0xF059D, text: Math.round(root.weather.wind) + " m/s" },
                      { icon: 0xF058E, text: Math.round(root.weather.humidity) + "%" }
                    ] : []
                    Row {
                      required property var modelData
                      spacing: Math.round(surface.u * 0.6)
                      Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.glyph(modelData.icon)
                        color: root.accent
                        font.family: root.fontFamily
                        font.pixelSize: Math.round(surface.u * 1.6)
                      }
                      Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.text
                        color: Commons.Util.alpha(root.fg, 0.75)
                        font.family: root.fontFamily
                        font.pixelSize: Math.round(surface.u * 1.3)
                      }
                    }
                  }
                }
              }

              // ---- three-day forecast
              Rectangle {
                visible: !!root.weather
                x: stack.weatherWidth
                anchors.verticalCenter: parent.verticalCenter
                width: 1
                height: parent.height - 2 * stack.pad
                color: Commons.Util.alpha(root.fg, 0.14)
              }

              Column {
                visible: !!root.weather
                x: stack.weatherWidth + Math.round(surface.u * 2.2)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Math.round(surface.u * 1.5)

                Repeater {
                  model: root.weather ? root.weather.forecast : []

                  Row {
                    required property var modelData
                    spacing: Math.round(surface.u * 1)

                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      width: Math.round(surface.u * 4)
                      text: modelData.day
                      color: Commons.Util.alpha(root.fg, 0.75)
                      font.family: root.fontFamily
                      font.pixelSize: Math.round(surface.u * 1.4)
                    }
                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      width: Math.round(surface.u * 2.8)
                      horizontalAlignment: Text.AlignHCenter
                      text: root.weatherIcon(modelData.code, true)
                      color: root.accent
                      font.family: root.fontFamily
                      font.pixelSize: Math.round(surface.u * 2.2)
                    }
                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      width: Math.round(surface.u * 3.6)
                      horizontalAlignment: Text.AlignRight
                      text: root.signed(modelData.max)
                      color: root.fg
                      font.family: root.fontFamily
                      font.pixelSize: Math.round(surface.u * 1.45)
                    }
                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      width: Math.round(surface.u * 3.6)
                      horizontalAlignment: Text.AlignRight
                      text: root.signed(modelData.min)
                      color: Commons.Util.alpha(root.fg, 0.55)
                      font.family: root.fontFamily
                      font.pixelSize: Math.round(surface.u * 1.45)
                    }
                  }
                }
              }
            }
          }

          CardSlot {
            key: "hardware"
            area: stack
            defaultX: (stack.lowerLeft + stack.weatherCardWidth + stack.gap + stack.hardwareWidth / 2) / stack.width
            defaultY: stack.lowerY

            GlassCard {
              unit: surface.u
              width: stack.hardwareWidth
              height: stack.cardHeight

              Column {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: stack.pad
                anchors.rightMargin: stack.pad
                spacing: Math.round(surface.u * 0.3)

                Meter {
                  width: parent.width
                  unit: surface.u
                  icon: root.glyph(0xF035B)  // chip
                  label: "CPU"
                  detail: root.cpuTemp < 0 ? "" : root.cpuTemp + "°C"
                  fraction: root.cpuPercent / 100
                  value: root.cpuPercent < 0 ? "—" : root.cpuPercent + "%"
                }
                Meter {
                  width: parent.width
                  unit: surface.u
                  icon: root.glyph(0xF061A)  // memory
                  label: "RAM"
                  detail: root.gbPair(root.memUsedGb, root.memTotalGb)
                  fraction: root.memPercent / 100
                  value: root.memPercent < 0 ? "—" : root.memPercent + "%"
                }
                Meter {
                  width: parent.width
                  unit: surface.u
                  icon: root.glyph(0xF08AE)  // graphics card
                  label: "GPU"
                  detail: root.gpu && !root.gpu.asleep ? root.gpu.temp + "°C" : ""
                  fraction: root.gpu && !root.gpu.asleep ? root.gpu.util / 100 : 0
                  value: !root.gpu ? "—" : root.gpu.asleep ? "sleep" : root.gpu.util + "%"
                }
                Meter {
                  width: parent.width
                  unit: surface.u
                  icon: root.glyph(0xF061A)  // memory
                  label: "VRAM"
                  detail: root.gpu && !root.gpu.asleep ? root.gbPair(root.gpu.memUsedGb, root.gpu.memTotalGb) : ""
                  fraction: root.gpu && !root.gpu.asleep ? root.gpu.memPercent / 100 : 0
                  value: !root.gpu || root.gpu.asleep ? "—" : root.gpu.memPercent + "%"
                }
                Meter {
                  width: parent.width
                  unit: surface.u
                  icon: root.glyph(0xF02CA)  // disk
                  label: "Disk"
                  detail: root.gbPair(root.diskUsedGb, root.diskTotalGb)
                  fraction: root.diskPercent / 100
                  value: root.diskPercent < 0 ? "—" : root.diskPercent + "%"
                }
              }
            }
          }

          CardSlot {
            key: "audio"
            area: stack
            defaultX: 0.5
            defaultY: 0.83

            GlassCard {
              unit: surface.u
              width: Math.round(surface.u * 56)
              height: Math.round(surface.u * 19)

              // Bars mirrored around the middle line; silence leaves a row
              // of small dots.
              Row {
                id: spectrum
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Math.round(surface.u * 2.4)
                height: Math.round(surface.u * 8)
                spacing: Math.round(surface.u * 0.45)

                readonly property real barWidth: (width - spacing * (root.cavaBars - 1)) / root.cavaBars

                Repeater {
                  model: root.cavaBars

                  Item {
                    required property int index
                    width: spectrum.barWidth
                    height: spectrum.height

                    Rectangle {
                      readonly property real level: (root.cavaLevels[parent.index] || 0) / 100
                      anchors.centerIn: parent
                      width: parent.width
                      height: Math.max(width, parent.height * level)
                      radius: width / 2
                      color: Commons.Util.alpha(root.accent, 0.55 + 0.45 * level)
                    }
                  }
                }
              }

              Item {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: Math.round(surface.u * 2.4)
                height: Math.round(surface.u * 4.6)

                Column {
                  anchors.left: parent.left
                  anchors.right: mediaControls.left
                  anchors.rightMargin: Math.round(surface.u * 2)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Math.round(surface.u * 0.3)

                  Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: root.player ? root.player.trackTitle : "Nothing playing"
                    color: root.player ? root.fg : Commons.Util.alpha(root.fg, 0.55)
                    font.family: root.fontFamily
                    font.pixelSize: Math.round(surface.u * 1.6)
                  }
                  Text {
                    width: parent.width
                    visible: !!root.player && !!root.player.trackArtist
                    elide: Text.ElideRight
                    text: root.player ? root.player.trackArtist || "" : ""
                    color: Commons.Util.alpha(root.fg, 0.65)
                    font.family: root.fontFamily
                    font.pixelSize: Math.round(surface.u * 1.3)
                  }
                }

                Row {
                  id: mediaControls
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Math.round(surface.u * 0.6)
                  opacity: root.player ? 1 : 0.35

                  Repeater {
                    model: [
                      { action: "previous", icon: 0xF04AE, big: false },
                      { action: "toggle", icon: root.playing ? 0xF03E4 : 0xF040A, big: true },
                      { action: "next", icon: 0xF04AD, big: false }
                    ]

                    Rectangle {
                      required property var modelData
                      width: Math.round(surface.u * (modelData.big ? 4.6 : 3.8))
                      height: width
                      radius: width / 2
                      color: modelData.big ? Commons.Util.alpha(root.accent, buttonArea.containsMouse ? 0.35 : 0.2)
                        : Commons.Util.alpha(root.fg, buttonArea.containsMouse ? 0.14 : 0)

                      Text {
                        anchors.centerIn: parent
                        text: root.glyph(modelData.icon)
                        color: root.fg
                        font.family: root.fontFamily
                        font.pixelSize: Math.round(surface.u * (modelData.big ? 2.6 : 2.2))
                      }

                      MouseArea {
                        id: buttonArea
                        anchors.fill: parent
                        enabled: !!root.player && !root.editing
                        hoverEnabled: true
                        onClicked: {
                          if (modelData.action === "previous") root.player.previous()
                          else if (modelData.action === "next") root.player.next()
                          else root.player.togglePlaying()
                        }
                      }
                    }
                  }
                }
              }
            }
          }

          // ---- calendar
          CardSlot {
            key: "calendar"
            area: stack
            defaultX: 0.5
            defaultY: 0.4

            GlassCard {
              unit: surface.u
              width: Math.round(surface.u * 36)
              height: calendarColumn.height + 2 * stack.pad

              Column {
                id: calendarColumn
                x: stack.pad
                y: stack.pad
                width: parent.width - 2 * stack.pad
                spacing: Math.round(surface.u * 1.2)

                Item {
                  id: calendarHeader
                  width: parent.width
                  height: Math.round(surface.u * 3)

                  // Month title; a click returns to this month.
                  Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.locale.toString(root.shownMonth, "MMMM yyyy")
                    color: root.monthOffset === 0 ? root.fg : root.accent
                    font.family: root.fontFamily
                    font.pixelSize: Math.round(surface.u * 1.8)

                    MouseArea {
                      anchors.fill: parent
                      enabled: !root.editing && root.monthOffset !== 0
                      onClicked: root.monthOffset = 0
                    }
                  }

                  Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Math.round(surface.u * 0.4)

                    Repeater {
                      model: [
                        { step: -1, icon: 0xF0141 },  // chevron left
                        { step: 1, icon: 0xF0142 }    // chevron right
                      ]

                      Rectangle {
                        required property var modelData
                        width: Math.round(surface.u * 3)
                        height: width
                        radius: width / 2
                        color: Commons.Util.alpha(root.fg, pageArea.containsMouse ? 0.14 : 0)

                        Text {
                          anchors.centerIn: parent
                          text: root.glyph(modelData.icon)
                          color: Commons.Util.alpha(root.fg, 0.75)
                          font.family: root.fontFamily
                          font.pixelSize: Math.round(surface.u * 2)
                        }

                        MouseArea {
                          id: pageArea
                          anchors.fill: parent
                          enabled: !root.editing
                          hoverEnabled: true
                          onClicked: root.monthOffset += modelData.step
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
                      height: Math.round(surface.u * 2.6)
                      horizontalAlignment: Text.AlignHCenter
                      verticalAlignment: Text.AlignVCenter
                      text: modelData
                      color: Commons.Util.alpha(root.fg, 0.5)
                      font.family: root.fontFamily
                      font.pixelSize: Math.round(surface.u * 1.2)
                    }
                  }

                  Repeater {
                    model: root.monthCells
                    Item {
                      required property var modelData
                      width: monthGrid.cell
                      height: Math.round(surface.u * 3.4)

                      Rectangle {
                        visible: modelData.today
                        anchors.centerIn: parent
                        width: Math.round(surface.u * 3)
                        height: width
                        radius: width / 2
                        color: root.accent
                      }

                      Text {
                        anchors.centerIn: parent
                        visible: modelData.day > 0
                        text: modelData.day
                        color: modelData.today ? root.bg : Commons.Util.alpha(root.fg, 0.85)
                        font.family: root.fontFamily
                        font.pixelSize: Math.round(surface.u * 1.35)
                        font.bold: modelData.today
                      }
                    }
                  }
                }
              }
            }
          }

        }
      }
    }
  }
}

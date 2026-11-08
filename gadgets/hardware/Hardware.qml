import QtQuick
import Quickshell.Io
import qs.Commons as Commons
import "../../kit"
import "HardwareModel.js" as Model

// Hardware gadget: CPU from /proc/stat deltas, memory from /proc/meminfo,
// package temperature from coretemp, the NVIDIA card from nvidia-smi, root
// filesystem from df. Polls every 2 s while on screen.
GlassCard {
  id: gadget

  // ---- gadget contract (see GadgetsWindow.qml)
  property var host: null
  readonly property real u: host ? host.u : 10
  readonly property bool active: !!host && host.active
  readonly property real defaultX: 0.67
  readonly property real defaultY: 0.63
  property Item clickArea: null

  readonly property real pad: Math.round(u * 2.6)

  // ---- data
  property int cpuPercent: -1
  property int cpuTemp: -1
  property var lastCpu: null
  property var mem: null
  property var gpu: null
  property var diskUsage: null

  FileView {
    id: statFile
    path: "/proc/stat"
    onLoaded: {
      var sample = Model.cpuSample(text())
      var percent = Model.cpuPercent(gadget.lastCpu, sample)
      if (percent >= 0) gadget.cpuPercent = percent
      gadget.lastCpu = sample
    }
  }

  FileView {
    id: memFile
    path: "/proc/meminfo"
    onLoaded: {
      var next = Model.memory(text())
      if (next) gadget.mem = next
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
        var next = Model.nvidia(text)
        if (next !== undefined) gadget.gpu = next
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
    onLoaded: gadget.cpuTemp = Math.round(Number(text()) / 1000)
  }

  Process {
    id: diskProc
    command: ["df", "-B1", "--output=used,size", "/"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var next = Model.disk(text)
        if (next) gadget.diskUsage = next
      }
    }
  }

  Timer {
    interval: 2000
    repeat: true
    triggeredOnStart: true
    running: gadget.active
    property int ticks: 0
    onTriggered: {
      statFile.reload()
      memFile.reload()
      if (tempFile.path) tempFile.reload()
      if (!gpuProc.running) gpuProc.running = true
      if (ticks++ % 30 === 0 && !diskProc.running) diskProc.running = true
    }
  }

  // ---- card
  readonly property bool gpuAwake: !!gpu && !gpu.asleep

  unit: u
  width: Math.round(u * 43.4)
  height: Math.round(u * 18.5)

  Column {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: gadget.pad
    anchors.rightMargin: gadget.pad
    spacing: Math.round(gadget.u * 0.3)

    Meter {
      width: parent.width
      unit: gadget.u
      icon: Model.glyph(0xF035B)  // chip
      label: "CPU"
      detail: gadget.cpuTemp < 0 ? "" : gadget.cpuTemp + "°C"
      fraction: gadget.cpuPercent / 100
      value: gadget.cpuPercent < 0 ? "—" : gadget.cpuPercent + "%"
    }
    Meter {
      width: parent.width
      unit: gadget.u
      icon: Model.glyph(0xF061A)  // memory
      label: "RAM"
      detail: gadget.mem ? Model.gbPair(gadget.mem.usedGb, gadget.mem.totalGb) : ""
      fraction: gadget.mem ? gadget.mem.percent / 100 : 0
      value: gadget.mem ? gadget.mem.percent + "%" : "—"
    }
    Meter {
      width: parent.width
      unit: gadget.u
      icon: Model.glyph(0xF08AE)  // graphics card
      label: "GPU"
      detail: gadget.gpuAwake ? gadget.gpu.temp + "°C" : ""
      fraction: gadget.gpuAwake ? gadget.gpu.util / 100 : 0
      value: !gadget.gpu ? "—" : gadget.gpu.asleep ? "sleep" : gadget.gpu.util + "%"
    }
    Meter {
      width: parent.width
      unit: gadget.u
      icon: Model.glyph(0xF061A)  // memory
      label: "VRAM"
      detail: gadget.gpuAwake ? Model.gbPair(gadget.gpu.memUsedGb, gadget.gpu.memTotalGb) : ""
      fraction: gadget.gpuAwake ? gadget.gpu.memPercent / 100 : 0
      value: gadget.gpuAwake ? gadget.gpu.memPercent + "%" : "—"
    }
    Meter {
      width: parent.width
      unit: gadget.u
      icon: Model.glyph(0xF02CA)  // disk
      label: "Disk"
      detail: gadget.diskUsage ? Model.gbPair(gadget.diskUsage.usedGb, gadget.diskUsage.totalGb) : ""
      fraction: gadget.diskUsage ? gadget.diskUsage.percent / 100 : 0
      value: gadget.diskUsage ? gadget.diskUsage.percent + "%" : "—"
    }
  }
}

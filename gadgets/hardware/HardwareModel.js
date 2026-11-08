.pragma library

// Pure helpers for the hardware gadget (see tests/).

function glyph(code) { return String.fromCodePoint(code) }

// "7.1 / 31 GB": one decimal below 10 GB, whole numbers above.
function gbPair(used, total) {
  function fmt(v) { return v < 10 ? v.toFixed(1) : String(Math.round(v)) }
  return used < 0 || total <= 0 ? "" : fmt(used) + " / " + fmt(total) + " GB"
}

// Idle and total jiffies from the first ("cpu") line of /proc/stat.
function cpuSample(statText) {
  var parts = String(statText || "").split("\n")[0].trim().split(/\s+/).slice(1).map(Number)
  var idle = parts[3] + (parts[4] || 0)
  var total = parts.reduce(function(a, b) { return a + b }, 0)
  return { idle: idle, total: total }
}

// CPU load in percent between two samples, or -1 without a usable pair.
function cpuPercent(previous, next) {
  if (!previous || !(next.total > previous.total)) return -1
  return Math.round(100 * (1 - (next.idle - previous.idle) / (next.total - previous.total)))
}

// { percent, usedGb, totalGb } from /proc/meminfo, or null.
function memory(meminfoText) {
  var raw = String(meminfoText || "")
  var total = Number((/MemTotal:\s+(\d+)/.exec(raw) || [0, 0])[1])
  var avail = Number((/MemAvailable:\s+(\d+)/.exec(raw) || [0, 0])[1])
  if (!(total > 0)) return null
  return {
    percent: Math.round(100 * (1 - avail / total)),
    usedGb: (total - avail) / 1048576,
    totalGb: total / 1048576
  }
}

// Output of the NVIDIA query: "" (no card) -> null, "sleep" -> asleep, else
// "util, memUsedMiB, memTotalMiB, temp". Returns undefined when unreadable,
// so the caller can keep its last reading.
function nvidia(text) {
  var raw = String(text || "").trim()
  if (raw === "") return null
  if (raw === "sleep") return { asleep: true }
  var parts = raw.split("\n")[0].split(",").map(function(p) { return Number(p.trim()) })
  if (parts.length !== 4 || parts.some(isNaN)) return undefined
  return {
    asleep: false,
    util: parts[0],
    memPercent: Math.round(100 * parts[1] / parts[2]),
    memUsedGb: parts[1] / 1024,
    memTotalGb: parts[2] / 1024,
    temp: parts[3]
  }
}

// { percent, usedGb, totalGb } from `df -B1 --output=used,size`, or null.
function disk(dfText) {
  var line = String(dfText || "").split("\n")[1]
  if (!line) return null
  var parts = line.trim().split(/\s+/).map(Number)
  if (parts.length !== 2 || !(parts[1] > 0)) return null
  return {
    percent: Math.round(100 * parts[0] / parts[1]),
    usedGb: parts[0] / 1073741824,
    totalGb: parts[1] / 1073741824
  }
}

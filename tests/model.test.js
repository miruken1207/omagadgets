// Run: node tests/model.test.js
const fs = require("fs")
const path = require("path")
const assert = require("assert")

// Load a `.pragma library` file and return the named functions.
function load(file, names) {
  const src = fs.readFileSync(path.join(__dirname, "..", file), "utf8").replace(/^\.pragma library\s*/, "")
  return new Function(src + "\nreturn { " + names.join(", ") + " }")()
}

const S = load("Settings.js", ["GADGETS", "findEntry", "resolveSettings", "entryFile"])
const W = load("gadgets/weather/WeatherModel.js", ["signed", "icon", "describe", "parseForecast"])
const H = load("gadgets/hardware/HardwareModel.js", ["gbPair", "cpuSample", "cpuPercent", "memory", "nvidia", "disk"])
const C = load("gadgets/calendar/CalendarModel.js", ["shiftedMonth", "monthCells"])

let failed = 0
function test(name, fn) {
  try { fn(); console.log("ok   " + name) } catch (e) { failed++; console.log("FAIL " + name + "\n     " + e.message) }
}

// ---- settings

test("resolveSettings fills defaults", () => {
  const cfg = S.resolveSettings({})
  assert.strictEqual(cfg.workspace, "home")
  assert.deepStrictEqual(cfg.gadgets, S.GADGETS)
  assert.deepStrictEqual(cfg.options.weather, {})
})

test("resolveSettings keeps known gadgets in drawing order", () => {
  const cfg = S.resolveSettings({ gadgets: ["calendar", "nope", "clock"] })
  assert.deepStrictEqual(cfg.gadgets, ["clock", "calendar"])
})

test("resolveSettings allows no gadgets at all", () => {
  assert.deepStrictEqual(S.resolveSettings({ gadgets: [] }).gadgets, [])
})

test("resolveSettings trims the workspace and ignores blanks", () => {
  assert.strictEqual(S.resolveSettings({ workspace: " desk " }).workspace, "desk")
  assert.strictEqual(S.resolveSettings({ workspace: "  " }).workspace, "home")
  assert.strictEqual(S.resolveSettings({ workspace: 3 }).workspace, "home")
})

test("resolveSettings passes per-gadget options through", () => {
  const cfg = S.resolveSettings({ clock: { format: "hh:mm" }, weather: [1] })
  assert.deepStrictEqual(cfg.options.clock, { format: "hh:mm" })
  assert.deepStrictEqual(cfg.options.weather, {})
})

test("findEntry picks this plugin's entry", () => {
  const text = JSON.stringify({ plugins: [{ id: "a" }, { id: "miruken1207.omagadgets", workspace: "x" }] })
  assert.strictEqual(S.findEntry(text, "miruken1207.omagadgets").workspace, "x")
  assert.deepStrictEqual(S.findEntry(text, "missing"), {})
  assert.deepStrictEqual(S.findEntry("not json", "a"), {})
})

test("entryFile maps a gadget to its QML file", () => {
  assert.strictEqual(S.entryFile("weather"), "gadgets/weather/Weather.qml")
  for (const g of S.GADGETS) assert.ok(fs.existsSync(path.join(__dirname, "..", S.entryFile(g))), g)
})

// ---- weather

test("signed temperatures", () => {
  assert.strictEqual(W.signed(4.4), "+4°")
  assert.strictEqual(W.signed(-2.6), "-3°")
  assert.strictEqual(W.signed(0.2), "0°")
})

test("weather codes", () => {
  assert.strictEqual(W.describe(3), "overcast")
  assert.strictEqual(W.describe(63), "rain")
  assert.strictEqual(W.describe(99), "thunderstorm")
  assert.notStrictEqual(W.icon(0, true), W.icon(0, false))
})

test("parseForecast reads Open-Meteo and skips today", () => {
  const text = JSON.stringify({
    current: { temperature_2m: 4, apparent_temperature: 1, relative_humidity_2m: 93, wind_speed_10m: 2, weather_code: 3, is_day: 0 },
    daily: {
      time: ["2026-11-08", "2026-11-09", "2026-11-10", "2026-11-11"],
      weather_code: [3, 2, 61, 71],
      temperature_2m_max: [5, 6, 4, 3],
      temperature_2m_min: [1, 2, 0, -1]
    }
  })
  const w = W.parseForecast(text, d => d.toISOString().slice(0, 10))
  assert.strictEqual(w.temperature, 4)
  assert.strictEqual(w.day, false)
  assert.strictEqual(w.forecast.length, 3)
  assert.deepStrictEqual(w.forecast[0], { day: "2026-11-09", code: 2, max: 6, min: 2 })
})

test("parseForecast rejects junk", () => {
  assert.strictEqual(W.parseForecast("", () => ""), null)
  assert.strictEqual(W.parseForecast("{}", () => ""), null)
})

// ---- hardware

test("gbPair formats sizes", () => {
  assert.strictEqual(H.gbPair(7.14, 31.2), "7.1 / 31 GB")
  assert.strictEqual(H.gbPair(-1, 31), "")
})

test("cpuPercent from two /proc/stat samples", () => {
  const a = H.cpuSample("cpu  100 0 100 700 100 0 0 0 0 0\ncpu0 1 2 3")
  const b = H.cpuSample("cpu  150 0 150 750 100 0 0 0 0 0\n")
  assert.deepStrictEqual(a, { idle: 800, total: 1000 })
  assert.strictEqual(H.cpuPercent(a, b), 67)
  assert.strictEqual(H.cpuPercent(null, b), -1)
  assert.strictEqual(H.cpuPercent(b, b), -1)
})

test("memory from /proc/meminfo", () => {
  const m = H.memory("MemTotal:       32000000 kB\nMemFree: 1 kB\nMemAvailable:   24000000 kB\n")
  assert.strictEqual(m.percent, 25)
  assert.ok(Math.abs(m.totalGb - 30.52) < 0.01)
  assert.strictEqual(H.memory(""), null)
})

test("nvidia query output", () => {
  assert.strictEqual(H.nvidia(""), null)
  assert.deepStrictEqual(H.nvidia("sleep\n"), { asleep: true })
  const g = H.nvidia("12, 2048, 8192, 47\n")
  assert.strictEqual(g.util, 12)
  assert.strictEqual(g.memPercent, 25)
  assert.strictEqual(g.memTotalGb, 8)
  assert.strictEqual(H.nvidia("garbage"), undefined)
})

test("disk from df", () => {
  const d = H.disk("     Used      1B-blocks\n 1073741824 4294967296\n")
  assert.strictEqual(d.percent, 25)
  assert.strictEqual(d.usedGb, 1)
  assert.strictEqual(H.disk("header only"), null)
})

// ---- calendar

test("monthCells: November 2026 starts on Sunday", () => {
  const now = new Date(2026, 10, 8)
  const cells = C.monthCells(C.shiftedMonth(now, 0), now)
  assert.strictEqual(cells.length % 7, 0)
  assert.strictEqual(cells.slice(0, 6).every(c => c.day === 0), true)
  assert.strictEqual(cells[6].day, 1)
  assert.strictEqual(cells.filter(c => c.today).length, 1)
  assert.strictEqual(cells.find(c => c.today).day, 8)
})

test("monthCells: no today in another month", () => {
  const now = new Date(2026, 10, 8)
  const cells = C.monthCells(C.shiftedMonth(now, 1), now)
  assert.strictEqual(cells.some(c => c.today), false)
  assert.strictEqual(cells.filter(c => c.day > 0).length, 31)
})

test("shiftedMonth crosses years", () => {
  const d = C.shiftedMonth(new Date(2026, 10, 8), 3)
  assert.strictEqual(d.getFullYear(), 2027)
  assert.strictEqual(d.getMonth(), 1)
})

if (failed) { console.log("\n" + failed + " failed"); process.exit(1) }
console.log("\nall passed")

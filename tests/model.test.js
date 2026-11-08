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
const R = load("gadgets/rates/RatesModel.js", ["DEFAULTS", "resolveOptions", "parseCbu", "coingeckoUrl", "parseCoingecko", "quote", "nominal", "formatAmount", "formatChange", "rows"])

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

// ---- rates

// CBU's real answer for 07.11.2026 (trimmed) and a CoinGecko answer.
const cbuText = JSON.stringify([
  { Ccy: "USD", Nominal: "1", Rate: "11987.16", Diff: "13.68", Date: "07.11.2026" },
  { Ccy: "RUB", Nominal: "1", Rate: "146.29", Diff: "-0.3", Date: "07.11.2026" },
  { Ccy: "IRR", Nominal: "10", Rate: "2.85", Diff: "0", Date: "07.11.2026" }
])
const cgText = JSON.stringify({
  bitcoin: { usd: 75845, usd_24h_change: 0.1817, rub: 6220597, rub_24h_change: 0.2937, uzs: 906823537, uzs_24h_change: 0.1817, last_updated_at: 1 },
  ethereum: { usd: 2230.66, usd_24h_change: -0.06 }
})
const cbu = R.parseCbu(cbuText)
const crypto = R.parseCoingecko(cgText)
const near = (a, b, eps) => assert.ok(Math.abs(a - b) < (eps || 1e-6), a + " != " + b)

test("resolveOptions defaults match the mockup", () => {
  assert.deepStrictEqual(R.resolveOptions({}), R.DEFAULTS)
  assert.deepStrictEqual(R.resolveOptions(null), R.DEFAULTS)
})

test("resolveOptions normalises codes and keeps coins out of tabs", () => {
  const o = R.resolveOptions({ tabs: ["usd", "BTC", "usd", "eur"], assets: ["eth", " sol ", "x"] })
  assert.deepStrictEqual(o.tabs, ["USD", "EUR"])
  assert.deepStrictEqual(o.assets, ["ETH", "SOL"])
  assert.deepStrictEqual(R.resolveOptions({ tabs: ["BTC"] }).tabs, R.DEFAULTS.tabs)
})

test("parseCbu reads rates per unit and the previous rate", () => {
  assert.strictEqual(cbu.date, "07.11.2026")
  assert.deepStrictEqual(cbu.rates.UZS, { rate: 1, prev: 1 })
  near(cbu.rates.USD.rate, 11987.16)
  near(cbu.rates.USD.prev, 11973.48)
  near(cbu.rates.IRR.rate, 0.285)
  assert.strictEqual(R.parseCbu("[]"), null)
  assert.strictEqual(R.parseCbu("<html>"), null)
})

test("parseCoingecko keys by ticker", () => {
  assert.strictEqual(crypto.BTC.uzs.price, 906823537)
  near(crypto.BTC.rub.change, 0.2937)
  assert.strictEqual(crypto.ETH.usd.price, 2230.66)
  assert.strictEqual(crypto.ETH.rub, undefined)
  assert.strictEqual(R.parseCoingecko("{}"), null)
})

test("coingeckoUrl asks for coins in every tab", () => {
  const url = R.coingeckoUrl(["UZS", "BTC", "ETH"], ["UZS", "RUB"])
  assert.ok(url.includes("ids=bitcoin,ethereum"))
  assert.ok(url.includes("vs_currencies=uzs,rub,usd"))
  assert.strictEqual(R.coingeckoUrl(["UZS", "RUB"], ["USD"]), "")
})

test("fiat cross rates go through UZS", () => {
  near(R.quote("USD", "UZS", cbu, null).price, 11987.16)
  near(R.quote("USD", "RUB", cbu, null).price, 81.9411, 1e-3)
  near(R.quote("UZS", "USD", cbu, null).price, 1 / 11987.16)
  near(R.quote("RUB", "UZS", cbu, null).change, (146.29 / 146.59 - 1) * 100)
  assert.strictEqual(R.quote("EUR", "UZS", cbu, null), null)
})

test("crypto: direct quote, else through USD", () => {
  assert.strictEqual(R.quote("BTC", "UZS", cbu, crypto).price, 906823537)
  const eth = R.quote("ETH", "RUB", cbu, crypto)
  near(eth.price, 2230.66 * 11987.16 / 146.29, 1e-6)
  assert.ok(eth.change !== null)
  assert.strictEqual(R.quote("BTC", "UZS", cbu, null), null)
})

test("nominal lifts tiny rates to at least 1", () => {
  assert.strictEqual(R.nominal(146.29), 1)
  assert.strictEqual(R.nominal(0.00684), 1000)
  assert.strictEqual(R.nominal(1 / 11987.16), 100000)
  assert.strictEqual(R.nominal(0), 1)
})

test("formatAmount groups thousands", () => {
  assert.strictEqual(R.formatAmount(906823537), "906\u00A0823\u00A0537")
  assert.strictEqual(R.formatAmount(11987.16), "11\u00A0987")
  assert.strictEqual(R.formatAmount(146.294), "146.29")
  assert.strictEqual(R.formatAmount(6.8357), "6.84")
})

test("formatChange arrows and rounding", () => {
  assert.deepStrictEqual(R.formatChange(0.114), { text: "▲0.11%", direction: 1 })
  assert.deepStrictEqual(R.formatChange(-0.2047), { text: "▼0.20%", direction: -1 })
  assert.deepStrictEqual(R.formatChange(0.001), { text: "0.00%", direction: 0 })
  assert.deepStrictEqual(R.formatChange(null), { text: "", direction: 0 })
})

test("rows skip the base and use a readable amount", () => {
  const r = R.rows(R.DEFAULTS.assets, "RUB", cbu, crypto)
  assert.deepStrictEqual(r.map(x => x.asset), ["UZS", "USD", "BTC", "ETH"])
  assert.strictEqual(r[0].amount, "1\u00A0000")
  assert.strictEqual(r[0].value, "6.84")
  assert.strictEqual(r[1].value, "81.94")
  assert.strictEqual(R.rows(["EUR"], "UZS", cbu, crypto)[0].value, "…")
})

if (failed) { console.log("\n" + failed + " failed"); process.exit(1) }
console.log("\nall passed")

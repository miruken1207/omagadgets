.pragma library

// Pure helpers for the rates gadget (see tests/).
//
// Fiat comes from the Central Bank of Uzbekistan, which quotes every
// currency in UZS, so any fiat pair is a cross rate through UZS. Crypto
// comes from CoinGecko, which can quote a coin in most fiat currencies.

var DEFAULTS = {
  tabs: ["UZS", "RUB", "USD"],
  assets: ["UZS", "RUB", "USD", "BTC", "ETH"]
}

// Ticker -> CoinGecko id for the coins the gadget knows.
var COINS = {
  BTC: "bitcoin",
  ETH: "ethereum",
  USDT: "tether",
  SOL: "solana",
  TON: "the-open-network",
  BNB: "binancecoin",
  XRP: "ripple",
  DOGE: "dogecoin",
  TRX: "tron",
  ADA: "cardano",
  LTC: "litecoin"
}

var CBU_URL = "https://cbu.uz/uz/arkhiv-kursov-valyut/json/"

function isCrypto(symbol) {
  return COINS.hasOwnProperty(symbol)
}

function codeList(value, fallback) {
  if (!Array.isArray(value)) return fallback.slice()
  var out = []
  value.forEach(function(v) {
    var code = String(v).trim().toUpperCase()
    if (/^[A-Z]{2,6}$/.test(code) && out.indexOf(code) === -1) out.push(code)
  })
  return out.length ? out : fallback.slice()
}

// The gadget's options with defaults filled in. Tabs are fiat only: a coin
// cannot be the currency prices are shown in.
function resolveOptions(options) {
  options = options && typeof options === "object" ? options : {}
  var tabs = codeList(options.tabs, DEFAULTS.tabs).filter(function(c) { return !isCrypto(c) })
  return {
    tabs: tabs.length ? tabs : DEFAULTS.tabs.slice(),
    assets: codeList(options.assets, DEFAULTS.assets)
  }
}

// CBU's JSON as { date: "07.11.2026", rates: { USD: { rate, prev } } } with
// UZS per one unit, now and at the previous publication. UZS itself is
// { 1, 1 }. Returns null when the text is not a CBU rate list.
function parseCbu(text) {
  var list
  try { list = JSON.parse(String(text || "")) } catch (e) { return null }
  if (!Array.isArray(list) || list.length === 0) return null
  var rates = { UZS: { rate: 1, prev: 1 } }
  var date = ""
  list.forEach(function(item) {
    var nominal = Number(item.Nominal) || 1
    var rate = Number(item.Rate)
    var diff = Number(item.Diff) || 0
    if (!item.Ccy || !(rate > 0)) return
    rates[String(item.Ccy)] = { rate: rate / nominal, prev: (rate - diff) / nominal }
    if (!date && item.Date) date = String(item.Date)
  })
  return Object.keys(rates).length > 1 ? { date: date, rates: rates } : null
}

// CoinGecko simple/price URL for the coins among `assets`, quoted in the
// tabs (and USD, for cross rates), or "" when there are no coins.
function coingeckoUrl(assets, tabs) {
  var ids = assets.filter(isCrypto).map(function(s) { return COINS[s] })
  if (!ids.length) return ""
  var vs = tabs.concat(["USD"]).map(function(c) { return c.toLowerCase() })
    .filter(function(c, i, all) { return all.indexOf(c) === i })
  return "https://api.coingecko.com/api/v3/simple/price?ids=" + ids.join(",")
    + "&vs_currencies=" + vs.join(",") + "&include_24hr_change=true"
}

// CoinGecko's answer as { BTC: { usd: { price, change } } }, keyed by
// ticker, or null when it holds no prices.
function parseCoingecko(text) {
  var data
  try { data = JSON.parse(String(text || "")) } catch (e) { return null }
  if (!data || typeof data !== "object") return null
  var out = {}
  Object.keys(COINS).forEach(function(symbol) {
    var entry = data[COINS[symbol]]
    if (!entry) return
    var quotes = {}
    Object.keys(entry).forEach(function(key) {
      if (/_/.test(key) || typeof entry[key] !== "number") return
      var change = entry[key + "_24h_change"]
      quotes[key] = { price: entry[key], change: typeof change === "number" ? change : null }
    })
    if (Object.keys(quotes).length) out[symbol] = quotes
  })
  return Object.keys(out).length ? out : null
}

// One unit of `asset` in `base`: { price, change } with change in percent
// (null if unknown), or null when there is no data for the pair.
function quote(asset, base, cbu, crypto) {
  var fx = cbu ? cbu.rates : null
  if (isCrypto(asset)) {
    var coin = crypto ? crypto[asset] : null
    if (!coin) return null
    var direct = coin[base.toLowerCase()]
    if (direct) return { price: direct.price, change: direct.change }
    // Not quoted in this currency: go through USD with CBU's rates.
    if (!coin.usd || !fx || !fx.USD || !fx[base]) return null
    var now = fx.USD.rate / fx[base].rate
    var before = fx.USD.prev / fx[base].prev
    var change = coin.usd.change === null ? null
      : ((1 + coin.usd.change / 100) * (now / before) - 1) * 100
    return { price: coin.usd.price * now, change: change }
  }
  if (!fx || !fx[asset] || !fx[base]) return null
  var price = fx[asset].rate / fx[base].rate
  var prev = fx[asset].prev / fx[base].prev
  return { price: price, change: prev > 0 ? (price / prev - 1) * 100 : null }
}

// The smallest power of ten that lifts `price` to at least 1, so tiny
// rates read as "1 000 UZS -> 6.84 RUB" rather than "1 UZS -> 0.0068 RUB".
function nominal(price) {
  var n = 1
  while (price > 0 && price * n < 1 && n < 1e9) n *= 10
  return n
}

// Groups thousands with a no-break space: 906823537 -> "906 823 537". (Not
// the narrow U+202F: JetBrainsMono, Omarchy's default font, has no glyph for it.)
function groupThousands(digits) {
  return digits.replace(/\B(?=(\d{3})+(?!\d))/g, "\u00A0")
}

// Whole numbers from 1 000 up, two decimals below.
function formatAmount(value) {
  if (value >= 1000) return groupThousands(String(Math.round(value)))
  var fixed = value.toFixed(2).split(".")
  return groupThousands(fixed[0]) + "." + fixed[1]
}

// { text: "▲0.11%", direction: 1 }; direction is 1, -1 or 0.
function formatChange(change) {
  if (change === null || change === undefined || isNaN(change)) return { text: "", direction: 0 }
  var rounded = Math.round(Math.abs(change) * 100) / 100
  if (rounded === 0) return { text: "0.00%", direction: 0 }
  return { text: (change > 0 ? "▲" : "▼") + rounded.toFixed(2) + "%", direction: change > 0 ? 1 : -1 }
}

// The rows of the card for `base`: every asset but the base itself.
//   [{ asset, amount: "1 000", value: "6.84", change: { text, direction } }]
// A row without data has value "…".
function rows(assets, base, cbu, crypto) {
  return assets.filter(function(a) { return a !== base }).map(function(asset) {
    var q = quote(asset, base, cbu, crypto)
    if (!q) return { asset: asset, amount: "1", value: "…", change: formatChange(null) }
    var n = nominal(q.price)
    return {
      asset: asset,
      amount: groupThousands(String(n)),
      value: formatAmount(q.price * n),
      change: formatChange(q.change)
    }
  })
}

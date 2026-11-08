.pragma library

// Pure helpers for reading omagadgets' settings. Nothing here touches QML
// objects, so the logic can be exercised with node (see tests/).

// Every gadget, in drawing order. Each one lives in gadgets/<id>/ with a
// <Id>.qml entry point (see entryFile).
var GADGETS = ["clock", "weather", "hardware", "media", "calendar", "rates"]

var DEFAULTS = {
  workspace: "home",   // named workspace the gadgets appear on
  gadgets: GADGETS     // which gadgets to show
}

// This plugin's entry from shell.json's plugins[], or {} when absent.
function findEntry(text, pluginId) {
  var config
  try { config = JSON.parse(String(text || "")) } catch (e) { return {} }
  var list = config && Array.isArray(config.plugins) ? config.plugins : []
  for (var i = 0; i < list.length; i++)
    if (list[i] && String(list[i].id || "") === pluginId) return list[i]
  return {}
}

function isObject(value) {
  return !!value && typeof value === "object" && !Array.isArray(value)
}

// Settings with defaults filled in:
//   workspace  name of the workspace to show the gadgets on
//   gadgets    enabled gadget ids, unknown ones dropped, in drawing order
//   options    per-gadget settings objects, from entry[<gadget id>]
function resolveSettings(entry) {
  entry = isObject(entry) ? entry : {}

  var workspace = typeof entry.workspace === "string" && entry.workspace.trim() !== ""
    ? entry.workspace.trim() : DEFAULTS.workspace

  var gadgets = DEFAULTS.gadgets.slice()
  if (Array.isArray(entry.gadgets)) {
    var wanted = entry.gadgets.map(function(g) { return String(g) })
    gadgets = GADGETS.filter(function(g) { return wanted.indexOf(g) !== -1 })
  }

  var options = {}
  GADGETS.forEach(function(g) { options[g] = isObject(entry[g]) ? entry[g] : {} })

  return { workspace: workspace, gadgets: gadgets, options: options }
}

// "weather" -> "gadgets/weather/Weather.qml"
function entryFile(gadget) {
  return "gadgets/" + gadget + "/" + gadget.charAt(0).toUpperCase() + gadget.slice(1) + ".qml"
}

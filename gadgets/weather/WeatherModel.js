.pragma library

// Pure helpers for the weather gadget (see tests/).

function glyph(code) { return String.fromCodePoint(code) }

// "+4°", "-3°", "0°"
function signed(t) {
  t = Math.round(t)
  return (t > 0 ? "+" : "") + t + "°"
}

// Nerd Font icon for a WMO weather code.
function icon(code, day) {
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

function describe(code) {
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

// Open-Meteo forecast URL for a { latitude, longitude } location.
function forecastUrl(location) {
  return "https://api.open-meteo.com/v1/forecast"
    + "?latitude=" + location.latitude
    + "&longitude=" + location.longitude
    + "&current=temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,weather_code,is_day"
    + "&daily=weather_code,temperature_2m_max,temperature_2m_min&forecast_days=4"
    + "&wind_speed_unit=ms&timezone=auto"
}

// The Open-Meteo response as what the card shows, or null if it is not one.
// dayName(date) formats a forecast day ("Mon").
function parseForecast(text, dayName) {
  var data
  try { data = JSON.parse(String(text || "")) } catch (e) { return null }
  var c = data && data.current
  var d = data && data.daily
  if (!c) return null
  // The next three days; index 0 is today.
  var forecast = []
  for (var i = 1; i < 4 && d && i < d.time.length; i++)
    forecast.push({
      day: dayName(new Date(d.time[i] + "T12:00:00")),
      code: d.weather_code[i],
      max: d.temperature_2m_max[i],
      min: d.temperature_2m_min[i]
    })
  return {
    forecast: forecast,
    temperature: c.temperature_2m,
    feelsLike: c.apparent_temperature,
    humidity: c.relative_humidity_2m,
    wind: c.wind_speed_10m,
    code: c.weather_code,
    day: c.is_day === 1
  }
}

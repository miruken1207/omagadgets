.pragma library

// Pure helpers for the calendar gadget (see tests/).

// The first day of the month `offset` months away from `now`.
function shiftedMonth(now, offset) {
  return new Date(now.getFullYear(), now.getMonth() + offset, 1)
}

// A month as Monday-first weeks: [{ day (0 = padding), today }], always a
// whole number of weeks. `month` is a Date anywhere in that month.
function monthCells(month, now) {
  var y = month.getFullYear(), m = month.getMonth()
  var current = now.getFullYear() === y && now.getMonth() === m
  var offset = (new Date(y, m, 1).getDay() + 6) % 7
  var days = new Date(y, m + 1, 0).getDate()
  var cells = []
  for (var i = 0; i < offset; i++) cells.push({ day: 0, today: false })
  for (var day = 1; day <= days; day++) cells.push({ day: day, today: current && day === now.getDate() })
  while (cells.length % 7 !== 0) cells.push({ day: 0, today: false })
  return cells
}

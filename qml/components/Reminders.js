.pragma library

// Reminders travel between Rust and QML as "<unix seconds>|<recurrence>".

function parse(stored) {
    const parts = (stored || "").split("|")
    const seconds = parseInt(parts[0], 10)
    if (!(seconds > 0)) return null
    return { date: new Date(seconds * 1000), recurrence: parts[1] || "none" }
}

function pad(value) {
    return value < 10 ? "0" + value : "" + value
}

function dateText(date) {
    return date.getFullYear() + "-" + pad(date.getMonth() + 1) + "-" + pad(date.getDate())
}

function timeText(date) {
    return pad(date.getHours()) + ":" + pad(date.getMinutes())
}

// A local date and time from "YYYY-MM-DD" and "HH:MM", or null when either
// is not a real calendar date or clock time.
function fromFields(dateString, timeString) {
    const d = /^(\d{4})-(\d{2})-(\d{2})$/.exec(dateString.trim())
    const t = /^(\d{1,2}):(\d{2})$/.exec(timeString.trim())
    if (!d || !t) return null
    const year = +d[1], month = +d[2] - 1, day = +d[3], hours = +t[1], minutes = +t[2]
    if (hours > 23 || minutes > 59) return null
    const date = new Date(year, month, day, hours, minutes, 0, 0)
    // Date rolls 2026-02-31 over into March; that is not what was typed.
    if (date.getFullYear() !== year || date.getMonth() !== month || date.getDate() !== day) return null
    return date
}

function recurrenceText(recurrence) {
    if (recurrence === "daily") return qsTr("every day")
    if (recurrence === "weekly") return qsTr("every week")
    if (recurrence === "monthly") return qsTr("every month")
    return ""
}

// Short, relative where it helps: "Today 14:30", "Tomorrow 09:00",
// "Mon 28 Sep 09:00", with the year only when it is not this year.
function describe(stored, now) {
    const reminder = parse(stored)
    if (!reminder) return ""
    now = now || new Date()
    const date = reminder.date
    const startOf = function(d) { return new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime() }
    const days = Math.round((startOf(date) - startOf(now)) / 86400000)
    let day
    if (days === 0) day = qsTr("Today")
    else if (days === 1) day = qsTr("Tomorrow")
    else if (days === -1) day = qsTr("Yesterday")
    else day = Qt.formatDate(date, date.getFullYear() === now.getFullYear() ? "ddd d MMM" : "d MMM yyyy")
    const repeat = recurrenceText(reminder.recurrence)
    return day + " " + timeText(date) + (repeat.length ? " · " + repeat : "")
}

// Shorter, for tight spaces: "Tomorrow 09:30", with ↻ when it repeats.
function describeShort(stored, now) {
    const reminder = parse(stored)
    if (!reminder) return ""
    const full = describe(reminder.date.getTime() / 1000 + "|none", now)
    return full + (reminder.recurrence !== "none" ? " ↻" : "")
}

// One-click choices, each a Date in the future.
function presets(now) {
    now = now || new Date()
    const at = function(daysAhead, hours) {
        return new Date(now.getFullYear(), now.getMonth(), now.getDate() + daysAhead, hours, 0, 0, 0)
    }
    const list = [{ label: qsTr("In 1 hour"), date: new Date(now.getTime() + 3600000) }]
    if (now.getHours() < 17) list.push({ label: qsTr("This evening"), date: at(0, 18) })
    list.push({ label: qsTr("Tomorrow morning"), date: at(1, 9) })
    list.push({ label: qsTr("Next week"), date: at(7, 9) })
    return list
}

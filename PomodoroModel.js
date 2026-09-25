// Pomodoro Timer Model & Helper Logic for Omarchy

function pad(num) {
  return num < 10 ? "0" + num : String(num);
}

function formatTime(seconds) {
  if (isNaN(seconds) || seconds <= 0) return "00:00";
  var s = Math.floor(seconds);
  var hours = Math.floor(s / 3600);
  var mins = Math.floor((s % 3600) / 60);
  var secs = s % 60;

  if (hours > 0) {
    return pad(hours) + ":" + pad(mins) + ":" + pad(secs);
  }
  return pad(mins) + ":" + pad(secs);
}

function formatRemainingHuman(seconds) {
  if (isNaN(seconds) || seconds <= 0) return "0s";
  var s = Math.floor(seconds);
  var mins = Math.floor(s / 60);
  var remainder = s % 60;

  if (mins > 0 && remainder > 0) {
    return mins + "m " + remainder + "s";
  } else if (mins > 0) {
    return mins + "m";
  }
  return remainder + "s";
}

var templates = [
  {
    id: "classic",
    name: "Classic",
    subtitle: "Traditional 25m focus + 5m break",
    work: 25,
    breakMinutes: 5,
    label: "25 + 5 min"
  },
  {
    id: "deep",
    name: "Deep Work",
    subtitle: "Extended 50m focus + 10m break",
    work: 50,
    breakMinutes: 10,
    label: "50 + 10 min"
  },
  {
    id: "balanced",
    name: "Balanced",
    subtitle: "1-hour block (45m focus + 15m break)",
    work: 45,
    breakMinutes: 15,
    label: "45 + 15 min"
  },
  {
    id: "sprint",
    name: "Sprint",
    subtitle: "Quick 20m sprint + 5m break",
    work: 20,
    breakMinutes: 5,
    label: "20 + 5 min"
  }
];

function defaultSettings() {
  return {
    showWhenIdle: true,
    defaultWork: 25,
    defaultBreak: 5,
    autoStartBreak: true,
    autoStartWork: false,
    soundAlert: true
  };
}

function parseDuration(input) {
  if (!input || typeof input !== "string") return null;
  var matches = input.match(/\d+/g);
  if (!matches || matches.length === 0) return null;

  var work = parseInt(matches[0], 10);
  var brk = matches.length > 1 ? parseInt(matches[1], 10) : 5;

  if (isNaN(work) || work <= 0) return null;
  if (isNaN(brk) || brk <= 0) brk = 5;

  return { work: work, breakMinutes: brk };
}

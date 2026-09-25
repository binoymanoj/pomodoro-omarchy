import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "PomodoroModel.js" as Model

BarWidget {
  id: root
  moduleName: "pomodoro"

  // Settings State
  property bool showWhenIdle: true
  property int defaultWork: 25
  property int defaultBreak: 5
  property bool autoStartBreak: true
  property bool autoStartWork: false
  property bool soundAlert: true

  // Pomodoro Runtime State
  property string phase: "idle" // "idle", "work", "break"
  property bool running: false
  property bool paused: false
  property int remainingSeconds: 25 * 60
  property int totalSeconds: 25 * 60
  property int workMinutes: 25
  property int breakMinutes: 5
  property double targetEnd: 0
  property int cycleCount: 0

  // Custom Template Stepper Values
  property int customWorkInput: 25
  property int customBreakInput: 5

  // Paths
  property string omarchyPath: Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy"
  readonly property string stateDir: {
    var xdgRun = Quickshell.env("XDG_RUNTIME_DIR")
    return (xdgRun && xdgRun.length > 0)
      ? (xdgRun + "/omarchy-pomodoro")
      : "/tmp/omarchy-pomodoro"
  }
  readonly property string stateFilePath: stateDir + "/state.json"

  // Visual Properties
  readonly property color barForeground: bar ? bar.barForeground : Color.foreground
  readonly property color workColor: Color.accent
  readonly property color breakColor: "#98c379"
  readonly property color currentPhaseColor: (phase === "break") ? breakColor : workColor

  readonly property string currentIcon: {
    if (paused) return "󰏤"
    if (phase === "break") return "󰤆"
    return "󰄉"
  }

  readonly property string formattedTime: Model.formatTime(remainingSeconds)
  readonly property bool isSessionActive: running || paused || (phase !== "idle")
  readonly property bool hasVisualContent: showWhenIdle || isSessionActive

  readonly property string tooltipString: {
    if (phase === "work") {
      return "Pomodoro: Focus Session (" + formattedTime + " remaining, Cycle #" + cycleCount + ")\nLeft-click: Controls & Templates • Right-click: Pause/Resume • Middle-click: Reset"
    } else if (phase === "break") {
      return "Pomodoro: Short Break (" + formattedTime + " remaining)\nLeft-click: Controls & Templates • Right-click: Pause/Resume • Middle-click: Reset"
    } else if (paused) {
      return "Pomodoro: Paused (" + formattedTime + " remaining)\nLeft-click: Controls & Templates • Right-click: Resume • Middle-click: Reset"
    }
    return "Pomodoro Timer: Idle\nLeft-click: Controls & Templates • Right-click: Quick start (25+5)"
  }

  // Popup Management
  property bool previewOpen: false
  property bool popoutSwitchClosing: false
  readonly property bool opened: previewOpen

  function open() {
    previewOpen = true
  }

  function close() {
    previewOpen = false
  }

  function toggle() {
    previewOpen ? close() : open()
  }

  function closeForPopoutSwitch() {
    popoutSwitchClosing = true
    close()
    Qt.callLater(function() { root.popoutSwitchClosing = false })
  }

  // Timer Tick
  Timer {
    id: tickTimer
    interval: 1000
    repeat: true
    running: true
    onTriggered: {
      if (!root.running || root.paused) return
      var now = Date.now()
      var rem = Math.max(0, Math.round((root.targetEnd - now) / 1000))
      root.remainingSeconds = rem

      if (rem <= 0) {
        root.handlePhaseComplete()
      }
    }
  }

  // Phase Handling
  function handlePhaseComplete() {
    root.running = false

    if (root.phase === "work") {
      root.cycleCount = root.cycleCount + 1
      root.playAlertSound()
      root.sendNotification(
        "Work Session Complete! (Cycle #" + root.cycleCount + ")",
        "Time for a " + root.breakMinutes + "-minute break. Stretch and recharge!",
        "󰤆"
      )

      if (root.autoStartBreak) {
        root.startBreakPhase()
      } else {
        root.phase = "break"
        root.totalSeconds = root.breakMinutes * 60
        root.remainingSeconds = root.totalSeconds
        root.targetEnd = 0
        root.paused = true
        root.running = false
        root.saveState()
      }
    } else if (root.phase === "break") {
      root.playAlertSound()
      root.sendNotification(
        "Break Finished!",
        "Ready to start your next work session (" + root.workMinutes + " min)?",
        "󰄉"
      )

      if (root.autoStartWork) {
        root.startWorkPhase()
      } else {
        root.phase = "idle"
        root.paused = false
        root.running = false
        root.remainingSeconds = root.workMinutes * 60
        root.totalSeconds = root.remainingSeconds
        root.targetEnd = 0
        root.saveState()
      }
    }
  }

  function playAlertSound() {
    if (root.soundAlert) {
      Quickshell.execDetached(["pw-play", "/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga"])
    }
  }

  function sendNotification(title, message, glyph) {
    var icon = glyph || "󰄉"
    Quickshell.execDetached([root.omarchyPath + "/bin/omarchy-notification-send", "-g", icon, title, message])
  }

  // Session Control API
  function startTimer(workMin, breakMin) {
    root.workMinutes = Math.max(1, parseInt(workMin) || root.defaultWork)
    root.breakMinutes = Math.max(1, parseInt(breakMin) || root.defaultBreak)
    root.startWorkPhase()
    root.sendNotification(
      "Pomodoro Started",
      "Focus for " + root.workMinutes + " minutes (" + root.breakMinutes + "m break). Let's go!",
      "󰄉"
    )
  }

  function startWorkPhase() {
    root.phase = "work"
    root.totalSeconds = root.workMinutes * 60
    root.remainingSeconds = root.totalSeconds
    root.targetEnd = Date.now() + (root.totalSeconds * 1000)
    root.paused = false
    root.running = true
    root.saveState()
  }

  function startBreakPhase() {
    root.phase = "break"
    root.totalSeconds = root.breakMinutes * 60
    root.remainingSeconds = root.totalSeconds
    root.targetEnd = Date.now() + (root.totalSeconds * 1000)
    root.paused = false
    root.running = true
    root.saveState()
  }

  function togglePause() {
    if (root.phase === "idle") {
      root.startTimer(root.workMinutes, root.breakMinutes)
      return
    }
    if (root.running) {
      root.pauseTimer()
    } else {
      root.resumeTimer()
    }
  }

  function pauseTimer() {
    if (!root.running || root.paused) return
    root.paused = true
    root.running = false
    root.targetEnd = 0
    root.saveState()
  }

  function resumeTimer() {
    if (root.phase === "idle") {
      root.startTimer(root.workMinutes, root.breakMinutes)
      return
    }
    root.paused = false
    root.running = true
    root.targetEnd = Date.now() + (root.remainingSeconds * 1000)
    root.saveState()
  }

  function stopTimer() {
    root.running = false
    root.paused = false
    root.phase = "idle"
    root.remainingSeconds = root.workMinutes * 60
    root.totalSeconds = root.remainingSeconds
    root.targetEnd = 0
    root.saveState()
  }

  function skipPhase() {
    if (root.phase === "work") {
      root.startBreakPhase()
    } else {
      root.startWorkPhase()
    }
  }

  // Shell IPC Target
  IpcHandler {
    target: "pomodoro"

    function start(workMin: string, breakMin: string): void {
      var w = parseInt(workMin) || root.defaultWork
      var b = parseInt(breakMin) || root.defaultBreak
      root.startTimer(w, b)
    }
    function startBreak(breakMin: string): void {
      var b = parseInt(breakMin) || root.breakMinutes || root.defaultBreak
      root.breakMinutes = Math.max(1, b)
      root.startBreakPhase()
    }
    function togglePause(): void { root.togglePause() }
    function pause(): void { root.pauseTimer() }
    function resume(): void { root.resumeTimer() }
    function stop(): void { root.stopTimer() }
    function skip(): void { root.skipPhase() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.reloadState() }
    function status(): string {
      return JSON.stringify({
        phase: root.phase,
        running: root.running,
        paused: root.paused,
        remainingSeconds: root.remainingSeconds,
        formatted: root.formattedTime,
        workMinutes: root.workMinutes,
        breakMinutes: root.breakMinutes,
        cycleCount: root.cycleCount
      })
    }
  }

  // State Persistence
  FileView {
    id: stateFile
    path: root.stateFilePath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadState(text())
    onFileChanged: reload()
  }

  function saveState() {
    var state = {
      phase: root.phase,
      running: root.running,
      paused: root.paused,
      remainingSeconds: root.remainingSeconds,
      totalSeconds: root.totalSeconds,
      workMinutes: root.workMinutes,
      breakMinutes: root.breakMinutes,
      targetEnd: root.targetEnd,
      cycleCount: root.cycleCount,
      updatedAt: Date.now()
    }
    stateFile.setText(JSON.stringify(state, null, 2) + "\n")
  }

  function reloadState() {
    stateFile.reload()
  }

  function loadState(raw) {
    if (!raw || raw.trim() === "") return
    try {
      var parsed = JSON.parse(raw)
      if (parsed && typeof parsed === "object") {
        root.phase = parsed.phase || "idle"
        root.paused = parsed.paused === true
        root.workMinutes = parsed.workMinutes || root.defaultWork
        root.breakMinutes = parsed.breakMinutes || root.defaultBreak
        root.cycleCount = parsed.cycleCount || 0
        root.totalSeconds = parsed.totalSeconds || (root.phase === "break" ? (root.breakMinutes * 60) : (root.workMinutes * 60))

        if (parsed.running && !parsed.paused && parsed.targetEnd > 0) {
          var now = Date.now()
          var rem = Math.max(0, Math.round((parsed.targetEnd - now) / 1000))
          root.remainingSeconds = rem
          root.targetEnd = parsed.targetEnd
          root.running = rem > 0
          if (rem <= 0) {
            root.handlePhaseComplete()
          }
        } else {
          root.running = false
          root.remainingSeconds = parsed.remainingSeconds !== undefined
            ? parsed.remainingSeconds
            : (root.phase === "break" ? (root.breakMinutes * 60) : (root.workMinutes * 60))
        }
      }
    } catch (e) {
      // Ignore parse errors on partial writes
    }
  }

  // Settings Synchronization
  function applySettings() {
    root.showWhenIdle = setting("showWhenIdle", true) === true
    root.defaultWork = parseInt(setting("defaultWork", 25)) || 25
    root.defaultBreak = parseInt(setting("defaultBreak", 5)) || 5
    root.autoStartBreak = setting("autoStartBreak", true) === true
    root.autoStartWork = setting("autoStartWork", false) === true
    root.soundAlert = setting("soundAlert", true) === true

    if (root.phase === "idle" && !root.running) {
      root.workMinutes = root.defaultWork
      root.breakMinutes = root.defaultBreak
      root.customWorkInput = root.defaultWork
      root.customBreakInput = root.defaultBreak
      root.remainingSeconds = root.defaultWork * 60
      root.totalSeconds = root.remainingSeconds
    }
  }

  onSettingsChanged: applySettings()

  Component.onCompleted: {
    applySettings()
    Quickshell.execDetached(["mkdir", "-p", root.stateDir])
    stateFile.reload()
  }

  // Widget Geometry
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  visible: hasVisualContent

  // Bar Button Component
  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: root.hasVisualContent
    tooltipText: root.tooltipString
    horizontalMargin: 8
    verticalPadding: 6

    fixedWidth: root.vertical ? -1 : (barContentRow.implicitWidth + button.scaledHorizontalMargin * 2)
    fixedHeight: root.vertical ? (barContentCol.implicitHeight + button.scaledVerticalPadding * 2) : -1

    onPressed: function(b) {
      if (b === Qt.RightButton) {
        root.togglePause()
      } else if (b === Qt.MiddleButton) {
        root.stopTimer()
      } else {
        root.toggle()
      }
    }

    // Horizontal Layout (Standard Bar)
    Row {
      id: barContentRow
      visible: !root.vertical
      anchors.centerIn: parent
      spacing: Style.space(6)

      // Phase Icon
      Text {
        text: root.currentIcon
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        color: root.isSessionActive ? root.currentPhaseColor : root.barForeground
        opacity: (root.phase === "idle" || root.paused) ? 0.75 : 1.0
        anchors.verticalCenter: parent.verticalCenter
      }

      // Remaining Time (Shown when active or when idle if timer is ready)
      Text {
        visible: root.isSessionActive
        textFormat: Text.PlainText
        text: root.formattedTime
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        color: root.isSessionActive ? root.barForeground : Qt.darker(root.barForeground, 1.3)
        opacity: root.paused ? 0.6 : 1.0
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    // Vertical Layout (Vertical Bar)
    Column {
      id: barContentCol
      visible: root.vertical
      anchors.centerIn: parent
      spacing: Style.space(2)

      Text {
        text: root.currentIcon
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        color: root.isSessionActive ? root.currentPhaseColor : root.barForeground
        anchors.horizontalCenter: parent.horizontalCenter
      }

      Text {
        visible: root.isSessionActive
        text: Math.ceil(root.remainingSeconds / 60) + "m"
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        color: root.barForeground
        anchors.horizontalCenter: parent.horizontalCenter
      }
    }

    // Bar Edge Marker when popup open
    Rectangle {
      id: openIndicator
      visible: root.previewOpen
      readonly property bool isVert: !!root.bar && root.bar.vertical
      color: root.currentPhaseColor
      anchors.bottom: isVert ? undefined : parent.bottom
      anchors.right: isVert ? parent.right : undefined
      anchors.horizontalCenter: isVert ? undefined : parent.horizontalCenter
      anchors.verticalCenter: isVert ? parent.verticalCenter : undefined
      width: isVert ? Style.space(2) : Math.max(Style.space(18), barContentRow.implicitWidth * 0.4)
      height: isVert ? Math.max(Style.space(18), barContentCol.implicitHeight * 0.4) : Style.space(2)
      radius: Style.cornerRadius > 0 ? 1 : 0
    }
  }

  // Popout Panel Window
  KeyboardPanel {
    id: previewPanel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.previewOpen
    focusTarget: keyCatcher
    contentWidth: previewPanel.fittedContentWidth(Style.space(350))
    contentHeight: previewPanel.fittedContentHeight(mainColumn.implicitHeight, Style.space(600))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()

      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Space) {
          root.togglePause()
          event.accepted = true
        } else if (event.key === Qt.Key_S) {
          root.skipPhase()
          event.accepted = true
        } else if (event.key === Qt.Key_R) {
          root.stopTimer()
          event.accepted = true
        } else if (event.key === Qt.Key_1) {
          root.startTimer(25, 5)
          event.accepted = true
        } else if (event.key === Qt.Key_2) {
          root.startTimer(50, 10)
          event.accepted = true
        } else if (event.key === Qt.Key_3) {
          root.startTimer(45, 15)
          event.accepted = true
        } else if (event.key === Qt.Key_4) {
          root.startTimer(20, 5)
          event.accepted = true
        }
      }

      Column {
        id: mainColumn
        width: parent.width
        spacing: Style.space(12)
        topPadding: Style.space(4)
        bottomPadding: Style.space(8)

        // 1. Header Row
        RowLayout {
          width: parent.width
          spacing: Style.space(10)

          Rectangle {
            width: Style.space(36)
            height: Style.space(36)
            radius: Style.cornerRadius > 0 ? Style.cornerRadius : Style.space(6)
            color: Qt.rgba(root.currentPhaseColor.r, root.currentPhaseColor.g, root.currentPhaseColor.b, 0.16)
            border.width: 1
            border.color: root.currentPhaseColor

            Text {
              anchors.centerIn: parent
              text: root.currentIcon
              font.family: Style.font.family
              font.pixelSize: Style.font.display
              color: root.currentPhaseColor
            }
          }

          Column {
            Layout.fillWidth: true
            spacing: Style.space(2)

            Text {
              textFormat: Text.PlainText
              text: "Pomodoro Timer"
              font.family: Style.font.family
              font.pixelSize: Style.font.heading
              font.bold: true
              color: Color.foreground
            }

            Text {
              textFormat: Text.PlainText
              text: {
                if (root.phase === "work") return "Focus Session • Cycle #" + root.cycleCount
                if (root.phase === "break") return "Short Break • Rest & recharge"
                if (root.paused) return "Session Paused"
                return "Ready to focus"
              }
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              color: Qt.darker(Color.foreground, 1.4)
            }
          }
        }

        // 2. Timer Countdown Card
        BorderSurface {
          width: parent.width
          implicitHeight: Style.space(90)
          radius: Style.cornerRadius
          color: Qt.rgba(Color.popups.border.r, Color.popups.border.g, Color.popups.border.b, 0.12)
          padding: Style.space(10)

          Column {
            anchors.centerIn: parent
            spacing: Style.space(4)

            // Large Digital Time Display
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              textFormat: Text.PlainText
              text: root.formattedTime
              font.family: Style.font.family
              font.pixelSize: Style.font.display * 1.5
              font.bold: true
              color: root.isSessionActive ? root.currentPhaseColor : Color.foreground
            }

            // Phase / Duration Subtext
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              textFormat: Text.PlainText
              text: {
                if (root.phase === "idle") return root.workMinutes + "m focus + " + root.breakMinutes + "m break"
                if (root.phase === "work") return root.workMinutes + " min focus period"
                return root.breakMinutes + " min break period"
              }
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              color: Qt.darker(Color.foreground, 1.5)
            }

            // Progress Bar
            Rectangle {
              width: Style.space(260)
              height: Style.space(4)
              radius: 2
              color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.15)
              anchors.horizontalCenter: parent.horizontalCenter

              Rectangle {
                height: parent.height
                radius: 2
                color: root.currentPhaseColor
                width: {
                  if (root.totalSeconds <= 0) return 0
                  var fraction = 1.0 - (root.remainingSeconds / root.totalSeconds)
                  return Math.max(0, Math.min(1.0, fraction)) * parent.width
                }
              }
            }
          }
        }

        // 3. Play / Pause / Skip / Reset Controls
        RowLayout {
          width: parent.width
          spacing: Style.space(8)

          // Play / Pause / Resume Button
          Button {
            Layout.fillWidth: true
            bordered: true
            active: root.running
            iconText: root.running ? "󰏤" : "󰐊"
            text: root.running ? "Pause" : (root.paused ? "Resume" : "Start")
            onClicked: root.togglePause()
          }

          // Skip Phase Button
          Button {
            Layout.fillWidth: true
            bordered: true
            iconText: "󰒭"
            text: "Skip"
            active: false
            opacity: root.isSessionActive ? 1.0 : 0.4
            onClicked: if (root.isSessionActive) root.skipPhase()
          }

          // Reset Button
          Button {
            Layout.fillWidth: true
            bordered: true
            iconText: "󰓛"
            text: "Reset"
            active: false
            opacity: root.isSessionActive ? 1.0 : 0.4
            onClicked: if (root.isSessionActive) root.stopTimer()
          }
        }

        PanelSeparator { foreground: Color.popups.border }

        // 4. Preset Templates
        PanelSectionHeader {
          text: "PRESET TEMPLATES"
          foreground: Color.foreground
        }

        Grid {
          width: parent.width
          columns: 2
          spacing: Style.space(8)

          // Template 1: Classic (25 + 5)
          Button {
            width: (parent.width - Style.space(8)) / 2
            bordered: true
            iconText: "󰄉"
            text: "25 + 5 min"
            active: root.workMinutes === 25 && root.breakMinutes === 5 && root.isSessionActive
            onClicked: root.startTimer(25, 5)
          }

          // Template 2: Deep Work (50 + 10)
          Button {
            width: (parent.width - Style.space(8)) / 2
            bordered: true
            iconText: "󰄉"
            text: "50 + 10 min"
            active: root.workMinutes === 50 && root.breakMinutes === 10 && root.isSessionActive
            onClicked: root.startTimer(50, 10)
          }

          // Template 3: Balanced (45 + 15)
          Button {
            width: (parent.width - Style.space(8)) / 2
            bordered: true
            iconText: "󰄉"
            text: "45 + 15 min"
            active: root.workMinutes === 45 && root.breakMinutes === 15 && root.isSessionActive
            onClicked: root.startTimer(45, 15)
          }

          // Template 4: Sprint (20 + 5)
          Button {
            width: (parent.width - Style.space(8)) / 2
            bordered: true
            iconText: "󰄉"
            text: "20 + 5 min"
            active: root.workMinutes === 20 && root.breakMinutes === 5 && root.isSessionActive
            onClicked: root.startTimer(20, 5)
          }
        }

        PanelSeparator { foreground: Color.popups.border }

        // 5. Custom Duration
        PanelSectionHeader {
          text: "CUSTOM DURATION"
          foreground: Color.foreground
        }

        Column {
          width: parent.width
          spacing: Style.space(8)

          RowLayout {
            width: parent.width
            spacing: Style.space(8)

            // Work Stepper Card
            BorderSurface {
              Layout.fillWidth: true
              implicitHeight: Style.space(36)
              radius: Style.cornerRadius
              color: Qt.rgba(Color.popups.border.r, Color.popups.border.g, Color.popups.border.b, 0.08)
              padding: Style.space(4)

              RowLayout {
                anchors.fill: parent
                spacing: Style.space(4)

                Text {
                  text: "Work"
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  color: Qt.darker(Color.foreground, 1.4)
                  Layout.leftMargin: Style.space(6)
                }

                Item { Layout.fillWidth: true }

                Button {
                  text: "-"
                  bordered: true
                  horizontalPadding: Style.space(6)
                  verticalPadding: Style.space(2)
                  onClicked: root.customWorkInput = Math.max(1, root.customWorkInput - 5)
                }

                Text {
                  textFormat: Text.PlainText
                  text: root.customWorkInput + "m"
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                  color: Color.foreground
                }

                Button {
                  text: "+"
                  bordered: true
                  horizontalPadding: Style.space(6)
                  verticalPadding: Style.space(2)
                  onClicked: root.customWorkInput = Math.min(180, root.customWorkInput + 5)
                }
              }
            }

            // Break Stepper Card
            BorderSurface {
              Layout.fillWidth: true
              implicitHeight: Style.space(36)
              radius: Style.cornerRadius
              color: Qt.rgba(Color.popups.border.r, Color.popups.border.g, Color.popups.border.b, 0.08)
              padding: Style.space(4)

              RowLayout {
                anchors.fill: parent
                spacing: Style.space(4)

                Text {
                  text: "Break"
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  color: Qt.darker(Color.foreground, 1.4)
                  Layout.leftMargin: Style.space(6)
                }

                Item { Layout.fillWidth: true }

                Button {
                  text: "-"
                  bordered: true
                  horizontalPadding: Style.space(6)
                  verticalPadding: Style.space(2)
                  onClicked: root.customBreakInput = Math.max(1, root.customBreakInput - 1)
                }

                Text {
                  textFormat: Text.PlainText
                  text: root.customBreakInput + "m"
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                  color: Color.foreground
                }

                Button {
                  text: "+"
                  bordered: true
                  horizontalPadding: Style.space(6)
                  verticalPadding: Style.space(2)
                  onClicked: root.customBreakInput = Math.min(60, root.customBreakInput + 1)
                }
              }
            }
          }

          // Full-width Start Custom Button
          Button {
            width: parent.width
            bordered: true
            active: true
            iconText: "󰐊"
            text: "Start Custom (" + root.customWorkInput + "m + " + root.customBreakInput + "m)"
            onClicked: root.startTimer(root.customWorkInput, root.customBreakInput)
          }
        }
      }
    }
  }
}

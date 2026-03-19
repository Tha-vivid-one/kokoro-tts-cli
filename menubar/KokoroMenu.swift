import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var daemonTimer: Timer?

    let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
    var ttsDir: String { "\(homeDir)/kokoro-tts-cli" }
    let menubarDir: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/kokoro-tts-cli/menubar"
    }()
    let pidFile = "/tmp/kokoro-daemon.pid"
    let socketFile = "/tmp/kokoro-daemon.sock"

    let activeColor = NSColor(red: 0.5176, green: 0.9412, blue: 0.6118, alpha: 1.0)
    let inactiveColor = NSColor(red: 0.5216, green: 0.5216, blue: 0.5216, alpha: 1.0)

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateIcon()
        buildMenu()

        daemonTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.updateIcon()
            self?.buildMenu()
        }
    }

    func isDaemonRunning() -> Bool {
        guard FileManager.default.fileExists(atPath: pidFile),
              let pidStr = try? String(contentsOfFile: pidFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
              let pid = Int32(pidStr) else {
            return false
        }
        return kill(pid, 0) == 0 && FileManager.default.fileExists(atPath: socketFile)
    }

    func updateIcon() {
        let running = isDaemonRunning()
        if let button = statusItem.button {
            let filename = running ? "Active.png" : "Inactive.png"
            let path = "\(menubarDir)/\(filename)"
            if let image = NSImage(contentsOfFile: path) {
                image.isTemplate = false
                image.size = NSSize(width: 18, height: 18)
                button.image = image
            }
        }
    }

    func buildMenu() {
        let menu = NSMenu()
        let running = isDaemonRunning()

        let statusStr = running ? "Daemon Running" : "Daemon Stopped"
        let statusItem = NSMenuItem(title: statusStr, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false

        let dotColor = running ? activeColor : inactiveColor
        let dotImage = NSImage(size: NSSize(width: 8, height: 8), flipped: false) { rect in
            dotColor.setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
        statusItem.image = dotImage

        menu.addItem(statusItem)
        menu.addItem(NSMenuItem.separator())

        let startTitle = running ? "Restart Daemon" : "Start Daemon"
        let startItem = NSMenuItem(title: startTitle, action: #selector(restartDaemon), keyEquivalent: "r")
        startItem.target = self
        menu.addItem(startItem)

        let stopDaemonItem = NSMenuItem(title: "Stop Daemon", action: #selector(stopDaemon), keyEquivalent: "d")
        stopDaemonItem.target = self
        stopDaemonItem.isEnabled = running
        menu.addItem(stopDaemonItem)

        menu.addItem(NSMenuItem.separator())

        let stopItem = NSMenuItem(title: "Stop Playback", action: #selector(stopPlayback), keyEquivalent: "s")
        stopItem.target = self
        menu.addItem(stopItem)

        let testItem = NSMenuItem(title: "Test TTS", action: #selector(testTTS), keyEquivalent: "t")
        testItem.target = self
        menu.addItem(testItem)

        menu.addItem(NSMenuItem.separator())

        let infoItem = NSMenuItem(title: "How It Works", action: #selector(showInfo), keyEquivalent: "i")
        infoItem.target = self
        menu.addItem(infoItem)

        let logItem = NSMenuItem(title: "Open Debug Log", action: #selector(openLog), keyEquivalent: "l")
        logItem.target = self
        menu.addItem(logItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Kokoro Menu", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        self.statusItem.menu = menu
    }

    @objc func restartDaemon() {
        if isDaemonRunning() {
            runScript("stop.sh")
            usleep(500_000)
        }
        DispatchQueue.global().async { [weak self] in
            guard let self = self else { return }
            self.runScript("warm.sh")
            DispatchQueue.main.async {
                self.updateIcon()
                self.buildMenu()
            }
        }
    }

    @objc func stopDaemon() {
        runScript("stop.sh")
        usleep(300_000)
        updateIcon()
        buildMenu()
    }

    @objc func stopPlayback() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        task.arguments = ["afplay"]
        try? task.run()
    }

    @objc func testTTS() {
        DispatchQueue.global().async { [weak self] in
            guard let self = self else { return }
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/bash")
            task.arguments = ["-c", "echo 'Kokoro is live and ready to speak.' | \"\(self.ttsDir)/speak.sh\""]
            try? task.run()
            task.waitUntilExit()
        }
    }

    @objc func showInfo() {
        let info = """
        Kokoro TTS — Local Voice Feedback for Claude Code

        HOW IT WORKS
        Every time Claude finishes a response, the Stop hook reads it and speaks a summary through Kokoro TTS. When you type a new prompt, playback cuts off immediately.

        DAEMON
        The warm daemon keeps the model loaded in memory for instant generation (~0.5s vs ~5s cold start). It auto-shuts down after 10 minutes idle — just restart it from this menu.

        CONTROLS
        • Start/Restart Daemon — loads the model into memory
        • Stop Playback — kills current audio immediately
        • Test TTS — speaks a test phrase

        VOICES & SPEED
        Change voice or speed from the terminal:
          echo "text" | ~/kokoro-tts-cli/speak.sh -v am_adam -s 1.5

        Available voices: af_heart (default), af_bella, af_nicole, am_adam, am_michael, bf_emma, bm_george

        DISABLE TTS
        Remove the hooks block from ~/.claude/settings.json or remove the TTS_SUMMARY block from ~/.claude/CLAUDE.md.

        DEBUG
        Check /tmp/kokoro-hook.log for hook output.
        """

        let alert = NSAlert()
        alert.messageText = "Kokoro TTS"
        alert.informativeText = info
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc func openLog() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-a", "Console", "/tmp/kokoro-hook.log"]
        try? task.run()
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    func runScript(_ script: String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = ["\(ttsDir)/\(script)"]
        task.currentDirectoryURL = URL(fileURLWithPath: ttsDir)
        try? task.run()
        task.waitUntilExit()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()

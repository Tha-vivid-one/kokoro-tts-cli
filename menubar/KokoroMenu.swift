import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var daemonTimer: Timer?
    var selectedVoice: String = "af_heart"

    let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
    var ttsDir: String { "\(homeDir)/kokoro-tts-cli" }
    let menubarDir: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/kokoro-tts-cli/menubar"
    }()
    let pidFile = "/tmp/kokoro-daemon.pid"
    let socketFile = "/tmp/kokoro-daemon.sock"
    let voiceFile = "/tmp/kokoro-voice.txt"

    let activeColor = NSColor(red: 0.5176, green: 0.9412, blue: 0.6118, alpha: 1.0)
    let inactiveColor = NSColor(red: 0.5216, green: 0.5216, blue: 0.5216, alpha: 1.0)

    let voices: [(id: String, label: String)] = [
        ("af_heart", "Heart (Female, US)"),
        ("af_bella", "Bella (Female, US)"),
        ("af_nicole", "Nicole (Female, US)"),
        ("af_sky", "Sky (Female, US)"),
        ("am_adam", "Adam (Male, US)"),
        ("am_michael", "Michael (Male, US)"),
        ("bf_emma", "Emma (Female, UK)"),
        ("bm_george", "George (Male, UK)"),
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        // Load saved voice
        if let saved = try? String(contentsOfFile: voiceFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           !saved.isEmpty {
            selectedVoice = saved
        }

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

    func saveVoice() {
        try? selectedVoice.write(toFile: voiceFile, atomically: true, encoding: .utf8)
    }

    func buildMenu() {
        let menu = NSMenu()
        let running = isDaemonRunning()

        // Status
        let statusStr = running ? "Daemon Running" : "Daemon Stopped"
        let statusMenuItem = NSMenuItem(title: statusStr, action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        let dotColor = running ? activeColor : inactiveColor
        let dotImage = NSImage(size: NSSize(width: 8, height: 8), flipped: false) { rect in
            dotColor.setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
        statusMenuItem.image = dotImage
        menu.addItem(statusMenuItem)
        menu.addItem(NSMenuItem.separator())

        // Toggle on/off
        let toggleTitle = running ? "Turn Off" : "Turn On"
        let toggleItem = NSMenuItem(title: toggleTitle, action: #selector(toggleDaemon), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)

        menu.addItem(NSMenuItem.separator())

        // Stop Playback
        let stopItem = NSMenuItem(title: "Stop Playback", action: #selector(stopPlayback), keyEquivalent: "s")
        stopItem.target = self
        menu.addItem(stopItem)

        // Test TTS
        let testItem = NSMenuItem(title: "Test TTS", action: #selector(testTTS), keyEquivalent: "t")
        testItem.target = self
        menu.addItem(testItem)

        menu.addItem(NSMenuItem.separator())

        // Voice submenu
        let voiceMenuItem = NSMenuItem(title: "Voice", action: nil, keyEquivalent: "")
        let voiceSubmenu = NSMenu()
        for voice in voices {
            let item = NSMenuItem(title: voice.label, action: #selector(selectVoice(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = voice.id
            if voice.id == selectedVoice {
                item.state = .on
            }
            voiceSubmenu.addItem(item)
        }
        voiceMenuItem.submenu = voiceSubmenu
        menu.addItem(voiceMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Info
        let infoItem = NSMenuItem(title: "How It Works", action: #selector(showInfo), keyEquivalent: "i")
        infoItem.target = self
        menu.addItem(infoItem)

        // Debug log
        let logItem = NSMenuItem(title: "Open Debug Log", action: #selector(openLog), keyEquivalent: "l")
        logItem.target = self
        menu.addItem(logItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit Kokoro Menu", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        self.statusItem.menu = menu
    }

    @objc func toggleDaemon() {
        if isDaemonRunning() {
            stopDaemon()
        } else {
            startDaemon()
        }
    }

    func startDaemon() {
        DispatchQueue.global().async { [weak self] in
            guard let self = self else { return }
            self.runScript("warm.sh")
            DispatchQueue.main.async {
                self.updateIcon()
                self.buildMenu()
            }
        }
    }

    func stopDaemon() {
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
            let voiceArg = self.selectedVoice
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/bash")
            task.arguments = ["-c", "echo 'Kokoro is live and ready to speak.' | \"\(self.ttsDir)/speak.sh\" -v \(voiceArg)"]
            try? task.run()
            task.waitUntilExit()
        }
    }

    @objc func selectVoice(_ sender: NSMenuItem) {
        guard let voiceId = sender.representedObject as? String else { return }
        selectedVoice = voiceId
        saveVoice()
        buildMenu()
    }

    @objc func showInfo() {
        let info = """
        Kokoro TTS — Local Voice Feedback for Claude Code

        HOW IT WORKS
        Every time Claude finishes a response, the Stop hook reads it and speaks a summary through Kokoro TTS. When you type a new prompt, playback cuts off immediately.

        ON / OFF
        Use "Turn On" / "Turn Off" to toggle TTS. When off (gray icon), responses won't be spoken. When on (green icon), the warm daemon is loaded for instant generation.

        VOICES
        Pick a voice from the Voice submenu. Your selection is saved between sessions.

        INTERRUPTING
        TTS is automatically interrupted when you send a new message. You can also click "Stop Playback" or use the keyboard shortcut.

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
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
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

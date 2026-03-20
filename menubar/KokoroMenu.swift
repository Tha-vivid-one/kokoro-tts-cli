import Cocoa

struct ClaudeSession {
    let sessionId: String
    let projectName: String
    let slug: String
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var daemonTimer: Timer?
    var selectedVoice: String = "af_heart"
    var mutedSessions: Set<String> = []
    var activeSessions: [ClaudeSession] = []

    let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
    var ttsDir: String { "\(homeDir)/Developer/tools/kokoro-tts-cli" }
    let menubarDir: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Developer/tools/kokoro-tts-cli/menubar"
    }()
    let pidFile = "/tmp/kokoro-daemon.pid"
    let socketFile = "/tmp/kokoro-daemon.sock"
    let voiceFile = "/tmp/kokoro-voice.txt"
    let muteFile = "/tmp/kokoro-muted-sessions.json"
    let queueDir = "/tmp/kokoro-queue"

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

        if let saved = try? String(contentsOfFile: voiceFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           !saved.isEmpty {
            selectedVoice = saved
        }

        loadMutedSessions()
        discoverSessions()
        updateIcon()
        buildMenu()

        daemonTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.discoverSessions()
            self?.updateIcon()
            self?.buildMenu()
        }
    }

    // MARK: - Daemon Status

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

    // MARK: - Session Discovery

    func discoverSessions() {
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = ["-c", "ps aux | grep -o '\\-\\-resume [^ ]*' | cut -d' ' -f2 | sort -u"]
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        let sessionIds = output.split(separator: "\n").map(String.init).filter { !$0.isEmpty }

        var sessions: [ClaudeSession] = []
        let projectsDir = "\(homeDir)/.claude/projects"

        for sid in sessionIds {
            // Find the transcript file
            let findTask = Process()
            let findPipe = Pipe()
            findTask.executableURL = URL(fileURLWithPath: "/bin/bash")
            findTask.arguments = ["-c", "ls \(projectsDir)/*/\(sid).jsonl 2>/dev/null | head -1"]
            findTask.standardOutput = findPipe
            findTask.standardError = FileHandle.nullDevice
            try? findTask.run()
            findTask.waitUntilExit()

            let findData = findPipe.fileHandleForReading.readDataToEndOfFile()
            let transcriptPath = String(data: findData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            guard !transcriptPath.isEmpty else { continue }

            // Read first few lines to find cwd and slug
            var projectName = "Unknown"
            var slug = ""

            if let fileHandle = FileHandle(forReadingAtPath: transcriptPath) {
                // Read first 4KB to find metadata
                let chunk = fileHandle.readData(ofLength: 4096)
                fileHandle.closeFile()
                if let text = String(data: chunk, encoding: .utf8) {
                    let lines = text.split(separator: "\n", maxSplits: 5)
                    for line in lines {
                        if let lineData = line.data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] {
                            if let cwd = json["cwd"] as? String, projectName == "Unknown" {
                                projectName = (cwd as NSString).lastPathComponent
                            }
                            if let s = json["slug"] as? String, slug.isEmpty {
                                slug = s
                            }
                            if projectName != "Unknown" && !slug.isEmpty { break }
                        }
                    }
                }
            }

            sessions.append(ClaudeSession(sessionId: sid, projectName: projectName, slug: slug))
        }

        activeSessions = sessions
    }

    // MARK: - Queue

    func queueCount() -> Int {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: queueDir) else { return 0 }
        return files.filter { $0.hasSuffix(".json") }.count
    }

    // MARK: - Mute Management

    func loadMutedSessions() {
        guard let data = FileManager.default.contents(atPath: muteFile),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [String] else {
            mutedSessions = []
            return
        }
        mutedSessions = Set(arr)
    }

    func saveMutedSessions() {
        let arr = Array(mutedSessions)
        if let data = try? JSONSerialization.data(withJSONObject: arr, options: []) {
            FileManager.default.createFile(atPath: muteFile, contents: data)
        }
    }

    func saveVoice() {
        try? selectedVoice.write(toFile: voiceFile, atomically: true, encoding: .utf8)
    }

    // MARK: - Menu

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

        // Stop Playback
        let stopItem = NSMenuItem(title: "Stop Playback", action: #selector(stopPlayback), keyEquivalent: "s")
        stopItem.target = self
        menu.addItem(stopItem)

        // Test TTS
        let testItem = NSMenuItem(title: "Test TTS", action: #selector(testTTS), keyEquivalent: "t")
        testItem.target = self
        menu.addItem(testItem)

        menu.addItem(NSMenuItem.separator())

        // Sessions section
        if !activeSessions.isEmpty {
            let sessionsHeader = NSMenuItem(title: "Sessions", action: nil, keyEquivalent: "")
            sessionsHeader.isEnabled = false
            menu.addItem(sessionsHeader)

            for session in activeSessions {
                let isMuted = mutedSessions.contains(session.sessionId)
                let label = session.slug.isEmpty
                    ? session.projectName
                    : "\(session.projectName) — \(session.slug)"
                let item = NSMenuItem(title: label, action: #selector(toggleSessionMute(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = session.sessionId

                // Load play/stop icon
                let iconName = isMuted ? "Stop.png" : "Play.png"
                let iconPath = "\(menubarDir)/\(iconName)"
                if let icon = NSImage(contentsOfFile: iconPath) {
                    icon.size = NSSize(width: 14, height: 14)
                    item.image = icon
                } else {
                    // Fallback: use text indicators
                    item.state = isMuted ? .off : .on
                }

                menu.addItem(item)
            }

            // Queue count
            let count = queueCount()
            if count > 0 {
                let queueItem = NSMenuItem(title: "Queue: \(count) item\(count == 1 ? "" : "s")", action: nil, keyEquivalent: "")
                queueItem.isEnabled = false
                menu.addItem(queueItem)
            }

            menu.addItem(NSMenuItem.separator())
        }

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

    // MARK: - Actions

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

    @objc func toggleSessionMute(_ sender: NSMenuItem) {
        guard let sessionId = sender.representedObject as? String else { return }
        if mutedSessions.contains(sessionId) {
            mutedSessions.remove(sessionId)
        } else {
            mutedSessions.insert(sessionId)
        }
        saveMutedSessions()
        buildMenu()
    }

    @objc func showInfo() {
        let info = """
        Kokoro TTS — Local Voice Feedback for Claude Code

        HOW IT WORKS
        Every time Claude finishes a response, the hook summarizes it via Gemma 3n (local LM Studio) and queues it for Kokoro TTS. Responses from multiple sessions are spoken in order.

        ON / OFF
        Use "Turn On" / "Turn Off" to toggle TTS. When off (gray icon), responses won't be spoken.

        SESSIONS
        All active Claude Code sessions are listed. Click a session to mute/unmute it. Muted sessions are silenced but still tracked.

        QUEUE
        Responses are queued and spoken in order. "Stop Playback" skips the current item; the queue continues.

        VOICES
        Pick a voice from the Voice submenu. Your selection is saved between sessions.

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

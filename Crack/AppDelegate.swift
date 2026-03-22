import AppKit
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var appState: AppState!

    // Menu item tags
    let tagEnable = 100
    let tagAbout = 200
    let tagStartup = 250
    let tagUpdate = 260
    let tagQuit = 300
    let tagSoundBase = 1000

    // Update checker
    static let currentVersion: String = {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }()
    static let repoOwner = "ronreiter"
    static let repoName = "crack"
    var latestRelease: (version: String, dmgURL: String, notes: String)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        appState = AppState()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if let img = NSImage(systemSymbolName: "door.left.hand.open", accessibilityDescription: "Crack") {
                img.isTemplate = true
                button.image = img
            } else {
                button.title = "Crack"
            }
        }

        buildMenu()
        checkForUpdates(silent: true)
    }

    func buildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let enableItem = NSMenuItem(title: appState.isEnabled ? "✅ Enabled" : "❌ Disabled", action: #selector(menuItemClicked(_:)), keyEquivalent: "")
        enableItem.target = self
        enableItem.tag = tagEnable
        enableItem.isEnabled = true
        menu.addItem(enableItem)

        menu.addItem(NSMenuItem.separator())

        // Volume slider
        let volumeLabel = NSMenuItem(title: "Volume", action: nil, keyEquivalent: "")
        volumeLabel.isEnabled = false
        menu.addItem(volumeLabel)

        let slider = NSSlider(value: Double(appState.volume), minValue: 0, maxValue: 1, target: self, action: #selector(volumeChanged(_:)))
        slider.frame = NSRect(x: 20, y: 0, width: 180, height: 24)
        let sliderView = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        sliderView.addSubview(slider)
        let sliderItem = NSMenuItem()
        sliderItem.view = sliderView
        menu.addItem(sliderItem)

        menu.addItem(NSMenuItem.separator())

        // Sound picker submenu
        let sounds = appState.availableSounds
        if sounds.count > 1 {
            let soundMenu = NSMenu()
            for (index, sound) in sounds.enumerated() {
                let item = NSMenuItem(title: sound.capitalized, action: #selector(menuItemClicked(_:)), keyEquivalent: "")
                item.target = self
                item.tag = tagSoundBase + index
                item.isEnabled = true
                item.state = sound == appState.selectedSound ? .on : .off
                soundMenu.addItem(item)
            }
            let soundItem = NSMenuItem(title: "Sound", action: nil, keyEquivalent: "")
            soundItem.submenu = soundMenu
            menu.addItem(soundItem)
            menu.addItem(NSMenuItem.separator())
        }

        let startupItem = NSMenuItem(title: "Start at Login", action: #selector(menuItemClicked(_:)), keyEquivalent: "")
        startupItem.target = self
        startupItem.tag = tagStartup
        startupItem.isEnabled = true
        startupItem.state = isLoginItemEnabled() ? .on : .off
        menu.addItem(startupItem)

        let updateTitle = latestRelease != nil ? "Update Available (\(latestRelease!.version))" : "Check for Updates…"
        let updateItem = NSMenuItem(title: updateTitle, action: #selector(menuItemClicked(_:)), keyEquivalent: "")
        updateItem.target = self
        updateItem.tag = tagUpdate
        updateItem.isEnabled = true
        menu.addItem(updateItem)

        menu.addItem(NSMenuItem.separator())

        let aboutItem = NSMenuItem(title: "About Crack", action: #selector(menuItemClicked(_:)), keyEquivalent: "")
        aboutItem.target = self
        aboutItem.tag = tagAbout
        aboutItem.isEnabled = true
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Crack", action: #selector(menuItemClicked(_:)), keyEquivalent: "q")
        quitItem.target = self
        quitItem.tag = tagQuit
        quitItem.isEnabled = true
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc func menuItemClicked(_ sender: NSMenuItem) {
        switch sender.tag {
        case tagEnable:
            appState.isEnabled.toggle()
            if let button = statusItem.button {
                let name = appState.isEnabled ? "door.left.hand.open" : "door.left.hand.closed"
                if let img = NSImage(systemSymbolName: name, accessibilityDescription: "Crack") {
                    img.isTemplate = true
                    button.image = img
                }
            }
            buildMenu()

        case tagStartup:
            toggleLoginItem()
            buildMenu()

        case tagUpdate:
            if let release = latestRelease, let url = URL(string: release.dmgURL) {
                NSWorkspace.shared.open(url)
            } else {
                checkForUpdates(silent: false)
            }

        case tagAbout:
            NSApp.activate(ignoringOtherApps: true)
            NSApp.orderFrontStandardAboutPanel(options: [
                .applicationName: "Crack",
                .applicationVersion: AppDelegate.currentVersion,
                .credits: NSAttributedString(string: "Makes your MacBook lid sound like a squeaky door.\n\n© 2026 Ron Reiter")
            ])

        case tagQuit:
            NSApplication.shared.terminate(nil)

        default:
            if sender.tag >= tagSoundBase {
                let index = sender.tag - tagSoundBase
                let sounds = appState.availableSounds
                if index >= 0, index < sounds.count {
                    appState.selectedSound = sounds[index]
                    buildMenu()
                }
            }
        }
    }

    func isLoginItemEnabled() -> Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    func toggleLoginItem() {
        if #available(macOS 13.0, *) {
            do {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                    NSLog("[Crack] Login item disabled")
                } else {
                    try SMAppService.mainApp.register()
                    NSLog("[Crack] Login item enabled")
                }
            } catch {
                NSLog("[Crack] Failed to toggle login item: %@", error.localizedDescription)
            }
        }
    }

    @objc func volumeChanged(_ sender: NSSlider) {
        appState.volume = Float(sender.doubleValue)
    }

    // MARK: - Update Checker

    func checkForUpdates(silent: Bool) {
        let urlStr = "https://api.github.com/repos/\(AppDelegate.repoOwner)/\(AppDelegate.repoName)/releases/latest"
        guard let url = URL(string: urlStr) else { return }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let self = self, let data = data, error == nil else {
                if !silent {
                    DispatchQueue.main.async {
                        let alert = NSAlert()
                        alert.messageText = "Update Check Failed"
                        alert.informativeText = "Could not reach GitHub. Please try again later."
                        alert.runModal()
                    }
                }
                return
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String else { return }

            let latest = tagName.replacingOccurrences(of: "v", with: "")
            let current = AppDelegate.currentVersion

            if self.isVersion(latest, newerThan: current) {
                // Find DMG asset
                var dmgURL = json["html_url"] as? String ?? ""
                if let assets = json["assets"] as? [[String: Any]] {
                    for asset in assets {
                        if let name = asset["name"] as? String, name.hasSuffix(".dmg"),
                           let downloadURL = asset["browser_download_url"] as? String {
                            dmgURL = downloadURL
                            break
                        }
                    }
                }
                let notes = json["body"] as? String ?? ""

                DispatchQueue.main.async {
                    self.latestRelease = (version: latest, dmgURL: dmgURL, notes: notes)
                    self.buildMenu()

                    NSApp.activate(ignoringOtherApps: true)
                    let alert = NSAlert()
                    alert.messageText = "Crack \(latest) Available"
                    alert.informativeText = "You're running \(current). Would you like to download the update?"
                    alert.addButton(withTitle: "Download")
                    alert.addButton(withTitle: "Later")
                    if alert.runModal() == .alertFirstButtonReturn {
                        if let url = URL(string: dmgURL) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            } else if !silent {
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "You're Up to Date"
                    alert.informativeText = "Crack \(current) is the latest version."
                    alert.runModal()
                }
            }
        }.resume()
    }

    private func isVersion(_ a: String, newerThan b: String) -> Bool {
        let aParts = a.split(separator: ".").compactMap { Int($0) }
        let bParts = b.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(aParts.count, bParts.count) {
            let av = i < aParts.count ? aParts[i] : 0
            let bv = i < bParts.count ? bParts[i] : 0
            if av > bv { return true }
            if av < bv { return false }
        }
        return false
    }
}

class AppState {
    var isEnabled = true {
        didSet {
            if !isEnabled { currentEngine.stop() }
        }
    }
    var volume: Float = 0.7
    var selectedSound: String = "Knuckle Crack" {
        didSet {
            NSLog("[Crack] Switching sound to: %@", selectedSound)
            currentEngine.stop()
            if let engine = engineMap[selectedSound] {
                currentEngine = engine
            }
        }
    }
    var sensorUnavailable = false
    var availableSounds: [String] = []

    static var synthNames: [String] {
        let crackNames = CrackPreset.all.map { $0.name }
        let fmNames = FMPreset.all.map { $0.name }
        let noiseNames = NoisePreset.all.map { $0.name }
        return crackNames + fmNames + noiseNames
    }

    func isSynthEngine(_ name: String) -> Bool {
        return engineMap[name] != nil
    }

    let lidSensor = LidAngleSensor()
    var engineMap: [String: CreakAudioEngine] = [:]
    var currentEngine: CreakAudioEngine!

    private var sensorTimer: DispatchSourceTimer?
    private var audioTimer: DispatchSourceTimer?
    private var lastAngle: Double?
    private var lastAngleTime: TimeInterval = 0
    private var lastChangeTime: TimeInterval = 0
    private var smoothedVelocity: Double = 0
    private var logCounter = 0
    private var isAudioActive = false
    private var isHighFreq = false

    private let silenceDelay: TimeInterval = 0.15
    private let highFreqDuration: TimeInterval = 10.0
    private let sensorQueue = DispatchQueue(label: "com.ronreiter.crack.sensor", qos: .userInteractive)

    init() {
        // Build engine map
        for p in CrackPreset.all {
            engineMap[p.name] = SynthCrackEngine(preset: p)
        }
        for p in FMPreset.all {
            engineMap[p.name] = FMSynthEngine(preset: p)
        }
        for p in NoisePreset.all {
            engineMap[p.name] = NoiseResonantEngine(preset: p)
        }

        let defaultName = "Door"
        currentEngine = engineMap[defaultName]!
        selectedSound = defaultName
        sensorUnavailable = !lidSensor.isAvailable
        availableSounds = AppState.synthNames
        startMonitoring()
    }

    private func startMonitoring() {
        setSensorRate(fast: false)
    }

    private func setSensorRate(fast: Bool) {
        sensorTimer?.cancel()
        sensorTimer = DispatchSource.makeTimerSource(queue: sensorQueue)
        let ms = fast ? 16 : 100  // 60fps vs 10fps
        sensorTimer?.schedule(deadline: .now(), repeating: .milliseconds(ms))
        sensorTimer?.setEventHandler { [weak self] in
            self?.pollSensor()
        }
        sensorTimer?.resume()
        isHighFreq = fast
        if fast {
            NSLog("[Crack] Sensor → 60fps")
        } else {
            NSLog("[Crack] Sensor → 10fps")
        }
    }

    private func switchToHighFreq() {
        guard !isHighFreq else { return }
        setSensorRate(fast: true)
    }

    private func switchToLowFreq() {
        guard isHighFreq else { return }
        setSensorRate(fast: false)
    }

    private func startAudioTick() {
        guard !isAudioActive else { return }
        isAudioActive = true
        audioTimer = DispatchSource.makeTimerSource(queue: .main)
        audioTimer?.schedule(deadline: .now(), repeating: .milliseconds(8))
        audioTimer?.setEventHandler { [weak self] in
            self?.currentEngine.tick()
        }
        audioTimer?.resume()
    }

    private func stopAudioTick() {
        guard isAudioActive else { return }
        isAudioActive = false
        audioTimer?.cancel()
        audioTimer = nil
    }

    private func pollSensor() {
        guard isEnabled else { return }

        let angle = lidSensor.readAngle()
        guard angle >= 0 else { return }

        let now = ProcessInfo.processInfo.systemUptime

        defer {
            lastAngle = angle
            lastAngleTime = now
        }

        guard let prevAngle = lastAngle else { return }

        let dt = now - lastAngleTime
        guard dt > 0 else { return }

        let delta = abs(angle - prevAngle)

        if delta > 0.02 {
            let instantVel = delta / dt
            smoothedVelocity = smoothedVelocity * 0.6 + instantVel * 0.4
            lastChangeTime = now

            // Switch to high frequency polling on movement
            switchToHighFreq()

            let rate = mapVelocityToRate(smoothedVelocity)
            if logCounter % 30 == 0 {
                NSLog("[Crack] PLAY delta=%.4f° vel=%.3f°/s smooth=%.3f rate=%.2f", delta, instantVel, smoothedVelocity, rate)
            }
            logCounter += 1
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.startAudioTick()
                self.currentEngine.play(rate: rate, volume: self.volume)
            }
        } else if now - lastChangeTime > silenceDelay {
            smoothedVelocity = 0
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.currentEngine.stop()
                self.stopAudioTick()
            }
            // Drop back to low frequency after no movement for highFreqDuration
            if isHighFreq && now - lastChangeTime > highFreqDuration {
                switchToLowFreq()
            }
        }
    }

    private func mapVelocityToRate(_ velocity: Double) -> Float {
        return Float(max(0.1, velocity * 0.4))
    }
}

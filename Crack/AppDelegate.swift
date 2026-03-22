import AppKit
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var appState: AppState!

    // Menu item tags
    let tagEnable = 100
    let tagAbout = 200
    let tagStartup = 250
    let tagQuit = 300
    let tagSoundBase = 1000

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

        case tagAbout:
            NSApp.activate(ignoringOtherApps: true)
            NSApp.orderFrontStandardAboutPanel(options: [
                .applicationName: "Crack",
                .applicationVersion: "1.0.0",
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

    private var timer: Timer?
    private var lastAngle: Double?
    private var lastAngleTime: TimeInterval = 0
    private var lastChangeTime: TimeInterval = 0
    private var smoothedVelocity: Double = 0
    private var logCounter = 0

    private let silenceDelay: TimeInterval = 0.15

    init() {
        // Build engine map — engines are created lazily on first access
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
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.update()
        }
    }

    private func update() {
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

        currentEngine.tick()

        let delta = abs(angle - prevAngle)

        if delta > 0.005 {
            let instantVel = delta / dt
            smoothedVelocity = smoothedVelocity * 0.6 + instantVel * 0.4
            lastChangeTime = now

            let rate = mapVelocityToRate(smoothedVelocity)
            if logCounter % 30 == 0 {
                NSLog("[Crack] PLAY delta=%.4f° vel=%.3f°/s smooth=%.3f rate=%.2f", delta, instantVel, smoothedVelocity, rate)
            }
            logCounter += 1
            currentEngine.play(rate: rate, volume: volume)
        } else if now - lastChangeTime > silenceDelay {
            smoothedVelocity = 0
            currentEngine.stop()
        }
    }

    private func mapVelocityToRate(_ velocity: Double) -> Float {
        return Float(max(0.1, velocity * 0.4))
    }
}

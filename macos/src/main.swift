import Cocoa
import AVFoundation
import Carbon.HIToolbox
import ServiceManagement
import ApplicationServices

// MARK: - User Defaults Keys
struct Defaults {
    static let language = "whisperLanguage"
    static let modelPath = "whisperModelPath"
    static let playSounds = "playSounds"
}

// MARK: - Supported Languages (Whisper)
struct SupportedLanguages {
    static let codes: [String: String] = [
        "hu": "Magyar",
        "en": "English",
        "de": "Deutsch",
        "fr": "Français",
        "es": "Español",
        "it": "Italiano",
        "pt": "Português",
        "nl": "Nederlands",
        "pl": "Polski",
        "ru": "Русский",
        "uk": "Українська",
        "cs": "Čeština",
        "sk": "Slovenčina",
        "ro": "Română",
        "hr": "Hrvatski",
        "sr": "Srpski",
        "sl": "Slovenščina",
        "ja": "日本語",
        "zh": "中文",
        "ko": "한국어",
        "ar": "العربية",
        "tr": "Türkçe",
        "vi": "Tiếng Việt",
        "th": "ไทย",
        "el": "Ελληνικά",
        "he": "עברית",
        "hi": "हिन्दी",
        "sv": "Svenska",
        "da": "Dansk",
        "fi": "Suomi",
        "no": "Norsk"
    ]

    static func isValid(_ code: String) -> Bool {
        return codes.keys.contains(code.lowercased())
    }

    static var sortedCodes: [(code: String, name: String)] {
        return codes.sorted { $0.value < $1.value }.map { (code: $0.key, name: $0.value) }
    }
}

// MARK: - App Delegate
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var audioRecorder: AVAudioRecorder?
    var isRecording = false
    var settingsWindow: NSWindow?

    // Use private temp directory with unique filename
    var audioFilePath: String {
        let tempDir = NSTemporaryDirectory()
        return (tempDir as NSString).appendingPathComponent("whisper-dictate-\(ProcessInfo.processInfo.processIdentifier).wav")
    }

    var language: String {
        get { UserDefaults.standard.string(forKey: Defaults.language) ?? "hu" }
        set { UserDefaults.standard.set(newValue, forKey: Defaults.language) }
    }

    var modelPath: String {
        get { UserDefaults.standard.string(forKey: Defaults.modelPath) ?? NSHomeDirectory() + "/.whisper-models/ggml-medium.bin" }
        set { UserDefaults.standard.set(newValue, forKey: Defaults.modelPath) }
    }

    var playSounds: Bool {
        get { UserDefaults.standard.object(forKey: Defaults.playSounds) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Defaults.playSounds) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        registerHotkey()
        requestMicrophonePermission()
        checkAccessibilityPermission()
        checkModelExists()

        NSLog("WhisperDictate started. Press ⌃⌥D to toggle recording.")
    }

    func applicationWillTerminate(_ notification: Notification) {
        cleanupAudioFile()
    }

    func cleanupAudioFile() {
        try? FileManager.default.removeItem(atPath: audioFilePath)
    }

    // MARK: - Status Item
    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🎤"

        let menu = NSMenu()

        menu.addItem(NSMenuItem(title: "Toggle Recording (⌃⌥D)", action: #selector(toggleRecording), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        let statusMenuItem = NSMenuItem(title: "Status: Ready", action: nil, keyEquivalent: "")
        statusMenuItem.tag = 100
        menu.addItem(statusMenuItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit WhisperDictate", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    // MARK: - Settings Window
    @objc func showSettings() {
        if settingsWindow == nil {
            settingsWindow = createSettingsWindow()
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func createSettingsWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 280),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "WhisperDictate Settings"
        window.center()

        let contentView = NSView(frame: window.contentView!.bounds)

        var y: CGFloat = 230
        let labelWidth: CGFloat = 120
        let controlX: CGFloat = 140
        let controlWidth: CGFloat = 280

        // Language
        let langLabel = NSTextField(labelWithString: "Language:")
        langLabel.frame = NSRect(x: 20, y: y, width: labelWidth, height: 24)
        contentView.addSubview(langLabel)

        let langPopup = NSPopUpButton(frame: NSRect(x: controlX, y: y, width: 180, height: 24), pullsDown: false)
        langPopup.tag = 1
        for lang in SupportedLanguages.sortedCodes {
            langPopup.addItem(withTitle: "\(lang.name) (\(lang.code))")
            langPopup.lastItem?.representedObject = lang.code
        }
        // Select current language
        if let index = SupportedLanguages.sortedCodes.firstIndex(where: { $0.code == language }) {
            langPopup.selectItem(at: index)
        }
        langPopup.target = self
        langPopup.action = #selector(languageChanged(_:))
        contentView.addSubview(langPopup)

        y -= 40

        // Model Path
        let modelLabel = NSTextField(labelWithString: "Model Path:")
        modelLabel.frame = NSRect(x: 20, y: y, width: labelWidth, height: 24)
        contentView.addSubview(modelLabel)

        let modelField = NSTextField(string: modelPath)
        modelField.frame = NSRect(x: controlX, y: y, width: controlWidth - 40, height: 24)
        modelField.tag = 2
        modelField.target = self
        modelField.action = #selector(modelPathChanged(_:))
        contentView.addSubview(modelField)

        let browseBtn = NSButton(title: "...", target: self, action: #selector(browseModel))
        browseBtn.frame = NSRect(x: controlX + controlWidth - 35, y: y, width: 35, height: 24)
        contentView.addSubview(browseBtn)

        y -= 40

        // Hotkey (display only)
        let hotkeyLabel = NSTextField(labelWithString: "Hotkey:")
        hotkeyLabel.frame = NSRect(x: 20, y: y, width: labelWidth, height: 24)
        contentView.addSubview(hotkeyLabel)

        let hotkeyDisplay = NSTextField(labelWithString: "⌃⌥D (Control + Option + D)")
        hotkeyDisplay.frame = NSRect(x: controlX, y: y, width: controlWidth, height: 24)
        contentView.addSubview(hotkeyDisplay)

        y -= 40

        // Play sounds
        let soundCheck = NSButton(checkboxWithTitle: "Play sound feedback", target: self, action: #selector(playSoundsChanged(_:)))
        soundCheck.frame = NSRect(x: controlX, y: y, width: controlWidth, height: 24)
        soundCheck.state = playSounds ? .on : .off
        contentView.addSubview(soundCheck)

        y -= 40

        // Launch at login
        let loginCheck = NSButton(checkboxWithTitle: "Launch at login", target: self, action: #selector(launchAtLoginChanged(_:)))
        loginCheck.frame = NSRect(x: controlX, y: y, width: controlWidth, height: 24)
        loginCheck.state = isLaunchAtLoginEnabled() ? .on : .off
        contentView.addSubview(loginCheck)

        // Model download hint
        let hintLabel = NSTextField(wrappingLabelWithString: "Model not found? Run: curl -L -o ~/.whisper-models/ggml-medium.bin https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin")
        hintLabel.frame = NSRect(x: 20, y: 15, width: 410, height: 40)
        hintLabel.font = NSFont.systemFont(ofSize: 10)
        hintLabel.textColor = .secondaryLabelColor
        contentView.addSubview(hintLabel)

        window.contentView = contentView
        return window
    }

    @objc func languageChanged(_ sender: NSPopUpButton) {
        if let code = sender.selectedItem?.representedObject as? String {
            language = code
            NSLog("Language changed to: \(language)")
        }
    }

    @objc func modelPathChanged(_ sender: NSTextField) {
        let newPath = sender.stringValue
        let validation = isValidModelPath(newPath)
        if validation.valid {
            modelPath = newPath
        }
        checkModelExists()
    }

    @objc func browseModel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select Whisper model file (.bin)"

        if panel.runModal() == .OK, let url = panel.url {
            modelPath = url.path
            if let contentView = settingsWindow?.contentView {
                for subview in contentView.subviews {
                    if let textField = subview as? NSTextField, textField.tag == 2 {
                        textField.stringValue = modelPath
                    }
                }
            }
            checkModelExists()
        }
    }

    @objc func playSoundsChanged(_ sender: NSButton) {
        playSounds = sender.state == .on
    }

    @objc func launchAtLoginChanged(_ sender: NSButton) {
        setLaunchAtLogin(sender.state == .on)
    }

    // MARK: - Launch at Login
    func isLaunchAtLoginEnabled() -> Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("Failed to set launch at login: \(error)")
            }
        }
    }

    // MARK: - Model Validation
    func isValidModelPath(_ path: String) -> (valid: Bool, error: String?) {
        // Check extension
        if !path.lowercased().hasSuffix(".bin") {
            return (false, "Model must be a .bin file")
        }

        // Check for path traversal attempts
        let normalized = (path as NSString).standardizingPath
        if normalized.contains("..") {
            return (false, "Invalid path")
        }

        // Check file exists
        if !FileManager.default.fileExists(atPath: normalized) {
            return (false, "Model not found")
        }

        return (true, nil)
    }

    func checkModelExists() {
        let validation = isValidModelPath(modelPath)
        if !validation.valid {
            updateStatus("⚠️ \(validation.error ?? "Invalid model")")
        } else {
            updateStatus("Ready")
        }
    }

    func updateStatus(_ status: String) {
        if let menu = statusItem.menu {
            for item in menu.items {
                if item.tag == 100 {
                    item.title = "Status: \(status)"
                }
            }
        }
    }

    // MARK: - Permissions
    func requestMicrophonePermission() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            if !granted {
                DispatchQueue.main.async {
                    self.showPermissionAlert(
                        title: "Microphone Access Required",
                        message: "WhisperDictate needs microphone access to record your voice.",
                        settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
                    )
                }
            }
        }
    }

    func checkAccessibilityPermission() {
        let trusted = AXIsProcessTrusted()
        if !trusted {
            showPermissionAlert(
                title: "Accessibility Access Required",
                message: "WhisperDictate needs accessibility access to paste transcribed text into other apps.",
                settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            )
        }
    }

    func showPermissionAlert(title: String, message: String, settingsURL: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: settingsURL) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    // MARK: - Hotkey Registration
    func registerHotkey() {
        var hotKeyRef: EventHotKeyRef?
        var gMyHotKeyID = EventHotKeyID()
        gMyHotKeyID.signature = OSType(0x57485044) // "WHPD"
        gMyHotKeyID.id = 1

        let modifiers: UInt32 = UInt32(controlKey | optionKey)
        let keyCode: UInt32 = 2 // D key

        RegisterEventHotKey(keyCode, modifiers, gMyHotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { (_, event, _) -> OSStatus in
            let appDelegate = NSApplication.shared.delegate as! AppDelegate
            DispatchQueue.main.async {
                appDelegate.toggleRecording()
            }
            return noErr
        }, 1, &eventType, nil, nil)
    }

    // MARK: - Recording
    @objc func toggleRecording() {
        if isRecording {
            stopRecordingAndTranscribe()
        } else {
            startRecording()
        }
    }

    func startRecording() {
        let audioURL = URL(fileURLWithPath: audioFilePath)
        try? FileManager.default.removeItem(at: audioURL)

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: audioURL, settings: settings)
            audioRecorder?.record()
            isRecording = true
            statusItem.button?.title = "🔴"
            updateStatus("Recording...")
            if playSounds { NSSound(named: "Tink")?.play() }
            NSLog("Recording started")
        } catch {
            NSLog("Recording failed: \(error)")
            if playSounds { NSSound(named: "Basso")?.play() }
        }
    }

    func stopRecordingAndTranscribe() {
        audioRecorder?.stop()
        isRecording = false
        statusItem.button?.title = "⏳"
        updateStatus("Transcribing...")
        if playSounds { NSSound(named: "Pop")?.play() }
        NSLog("Recording stopped, transcribing...")

        DispatchQueue.global(qos: .userInitiated).async {
            self.transcribe()
        }
    }

    // MARK: - Whisper CLI Detection
    func findWhisperCLI() -> String? {
        // Check common paths for whisper-cli
        let paths = [
            "/opt/homebrew/bin/whisper-cli",  // ARM Mac (M1/M2/M3)
            "/usr/local/bin/whisper-cli",      // Intel Mac
            "/opt/local/bin/whisper-cli",      // MacPorts
            NSHomeDirectory() + "/bin/whisper-cli"  // User local
        ]

        for path in paths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    // MARK: - Transcription
    func transcribe() {
        // Validate inputs before execution
        let modelValidation = isValidModelPath(modelPath)
        guard modelValidation.valid else {
            DispatchQueue.main.async {
                self.statusItem.button?.title = "🎤"
                self.updateStatus("⚠️ \(modelValidation.error ?? "Invalid model")")
                if self.playSounds { NSSound(named: "Basso")?.play() }
            }
            return
        }

        guard SupportedLanguages.isValid(language) else {
            DispatchQueue.main.async {
                self.statusItem.button?.title = "🎤"
                self.updateStatus("⚠️ Invalid language")
                if self.playSounds { NSSound(named: "Basso")?.play() }
            }
            return
        }

        guard let whisperPath = findWhisperCLI() else {
            DispatchQueue.main.async {
                self.statusItem.button?.title = "🎤"
                self.updateStatus("⚠️ whisper-cli not found")
                if self.playSounds { NSSound(named: "Basso")?.play() }
                NSLog("whisper-cli not found in PATH")
            }
            return
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: whisperPath)
        task.arguments = ["-m", modelPath, "-l", language.lowercased(), "-f", audioFilePath]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            let lines = output.components(separatedBy: "\n")
            var result = ""
            for line in lines {
                if line.hasPrefix("[") {
                    if let range = line.range(of: "]") {
                        let text = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                        result += text + " "
                    }
                }
            }
            result = result.trimmingCharacters(in: .whitespaces)

            // Cleanup audio file after transcription
            self.cleanupAudioFile()

            DispatchQueue.main.async {
                if !result.isEmpty {
                    self.pasteText(result)
                } else {
                    self.statusItem.button?.title = "🎤"
                    self.updateStatus("Ready")
                    if self.playSounds { NSSound(named: "Basso")?.play() }
                    NSLog("No speech recognized")
                }
            }
        } catch {
            // Cleanup even on error
            self.cleanupAudioFile()

            DispatchQueue.main.async {
                self.statusItem.button?.title = "🎤"
                self.updateStatus("Error")
                if self.playSounds { NSSound(named: "Basso")?.play() }
                NSLog("Transcription failed: \(error)")
            }
        }
    }

    // MARK: - Paste
    func pasteText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        NSLog("Transcribed: \(text)")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let source = CGEventSource(stateID: .hidSystemState)

            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
            keyDown?.flags = .maskCommand
            keyDown?.post(tap: .cghidEventTap)

            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
            keyUp?.flags = .maskCommand
            keyUp?.post(tap: .cghidEventTap)

            self.statusItem.button?.title = "🎤"
            self.updateStatus("Ready")
            if self.playSounds { NSSound(named: "Glass")?.play() }
        }
    }
}

// MARK: - Main
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

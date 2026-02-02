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

// MARK: - Whisper Models
struct WhisperModels {
    struct Model {
        let name: String
        let filename: String
        let size: String
        let url: String
        let pros: String
        let cons: String
    }

    static let available: [Model] = [
        Model(name: "Tiny",
              filename: "ggml-tiny.bin",
              size: "75 MB",
              url: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin",
              pros: "Very fast (~1 sec), small download",
              cons: "Lower accuracy, struggles with accents"),
        Model(name: "Base",
              filename: "ggml-base.bin",
              size: "142 MB",
              url: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin",
              pros: "Fast (~2 sec), good for clear speech",
              cons: "May miss some words in noisy audio"),
        Model(name: "Small",
              filename: "ggml-small.bin",
              size: "466 MB",
              url: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin",
              pros: "Good balance of speed and accuracy",
              cons: "Slower on Intel Macs"),
        Model(name: "Medium (Recommended)",
              filename: "ggml-medium.bin",
              size: "1.5 GB",
              url: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin",
              pros: "Best price/performance, handles accents well",
              cons: "Larger download, slower on older Macs"),
        Model(name: "Large",
              filename: "ggml-large-v3.bin",
              size: "3.1 GB",
              url: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin",
              pros: "Maximum accuracy for difficult audio",
              cons: "Very large, slow, minimal improvement over Medium")
    ]

    static var modelsDirectory: String {
        return NSHomeDirectory() + "/.whisper-models"
    }

    static func installedModels() -> [(path: String, name: String, size: String)] {
        var result: [(path: String, name: String, size: String)] = []
        let fm = FileManager.default
        let modelsDir = modelsDirectory

        guard let files = try? fm.contentsOfDirectory(atPath: modelsDir) else {
            return result
        }

        for file in files where file.hasSuffix(".bin") {
            let path = (modelsDir as NSString).appendingPathComponent(file)

            // Get file size
            var sizeStr = ""
            if let attrs = try? fm.attributesOfItem(atPath: path),
               let size = attrs[.size] as? Int64 {
                if size > 1_000_000_000 {
                    sizeStr = String(format: "%.1f GB", Double(size) / 1_000_000_000)
                } else {
                    sizeStr = String(format: "%.0f MB", Double(size) / 1_000_000)
                }
            }

            // Get friendly name
            var name = file.replacingOccurrences(of: "ggml-", with: "").replacingOccurrences(of: ".bin", with: "")
            name = name.capitalized

            result.append((path: path, name: name, size: sizeStr))
        }

        return result.sorted { $0.name < $1.name }
    }
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
class AppDelegate: NSObject, NSApplicationDelegate, URLSessionDownloadDelegate {
    var statusItem: NSStatusItem!
    var audioRecorder: AVAudioRecorder?
    var isRecording = false
    var settingsWindowController: NSWindowController?

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

        // First-run: check if model exists, if not show setup wizard
        if !hasAnyModel() {
            showFirstRunWizard()
        } else {
            checkModelExists()
        }

        NSLog("WhisperDictate started. Press ⌃⌥D to toggle recording.")
    }

    func hasAnyModel() -> Bool {
        let validation = isValidModelPath(modelPath)
        return validation.valid
    }

    // MARK: - First Run Wizard
    func showFirstRunWizard() {
        // Build description text
        var infoText = "To get started, download a Whisper speech recognition model:\n\n"
        for model in WhisperModels.available {
            infoText += "• \(model.name) (\(model.size))\n"
            infoText += "  ✓ \(model.pros)\n"
            infoText += "  ✗ \(model.cons)\n\n"
        }

        let alert = NSAlert()
        alert.messageText = "Welcome to WhisperDictate!"
        alert.informativeText = infoText
        alert.alertStyle = .informational

        // Add model options as buttons
        for model in WhisperModels.available.reversed() {
            alert.addButton(withTitle: "\(model.name) (\(model.size))")
        }
        alert.addButton(withTitle: "Cancel")

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()

        // Map response to model index (buttons are reversed)
        let modelCount = WhisperModels.available.count
        let buttonIndex = response.rawValue - 1000  // NSAlertFirstButtonReturn = 1000

        if buttonIndex < modelCount {
            let modelIndex = modelCount - 1 - buttonIndex
            let selectedModel = WhisperModels.available[modelIndex]
            downloadModel(selectedModel)
        } else {
            updateStatus("⚠️ No model selected")
        }
    }

    var downloadTask: URLSessionDownloadTask?
    var downloadSession: URLSession?
    var currentDownloadModel: WhisperModels.Model?
    var currentDownloadDestination: String?

    func downloadModel(_ model: WhisperModels.Model) {
        updateStatus("0% Downloading \(model.name)")
        statusItem.button?.title = "⬇️"

        // Create models directory
        let modelsDir = WhisperModels.modelsDirectory
        try? FileManager.default.createDirectory(atPath: modelsDir, withIntermediateDirectories: true)

        let destinationPath = (modelsDir as NSString).appendingPathComponent(model.filename)

        // Remove existing file if any
        try? FileManager.default.removeItem(atPath: destinationPath)

        guard let url = URL(string: model.url) else {
            updateStatus("⚠️ Invalid URL")
            return
        }

        // Store for delegate callbacks
        currentDownloadModel = model
        currentDownloadDestination = destinationPath

        let config = URLSessionConfiguration.default
        downloadSession = URLSession(configuration: config, delegate: self, delegateQueue: .main)
        downloadTask = downloadSession?.downloadTask(with: url)
        downloadTask?.resume()
    }

    // MARK: - URLSessionDownloadDelegate
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let model = currentDownloadModel else { return }
        let progress = totalBytesExpectedToWrite > 0 ? Int((Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)) * 100) : 0
        updateStatus("\(progress)% Downloading \(model.name)")
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let model = currentDownloadModel, let destinationPath = currentDownloadDestination else { return }
        let destinationURL = URL(fileURLWithPath: destinationPath)

        do {
            try FileManager.default.moveItem(at: location, to: destinationURL)
            modelPath = destinationPath
            statusItem.button?.title = "🎤"
            updateStatus("Ready - \(model.name)")
            if playSounds { NSSound(named: "Glass")?.play() }
            NSLog("Model downloaded: \(model.name)")
        } catch {
            statusItem.button?.title = "🎤"
            updateStatus("⚠️ Save failed")
            if playSounds { NSSound(named: "Basso")?.play() }
            NSLog("Save failed: \(error)")
        }

        currentDownloadModel = nil
        currentDownloadDestination = nil
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            statusItem.button?.title = "🎤"
            updateStatus("⚠️ Download failed")
            if playSounds { NSSound(named: "Basso")?.play() }
            NSLog("Download failed: \(error)")
            currentDownloadModel = nil
            currentDownloadDestination = nil
        }
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
        // Always create a fresh window to avoid zombie pointer issues
        let window = createSettingsWindow()
        settingsWindowController = NSWindowController(window: window)
        settingsWindowController?.showWindow(nil)
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

        // Model Selection
        let modelLabel = NSTextField(labelWithString: "Model:")
        modelLabel.frame = NSRect(x: 20, y: y, width: labelWidth, height: 24)
        contentView.addSubview(modelLabel)

        let installedModels = WhisperModels.installedModels()

        if installedModels.isEmpty {
            let noModelLabel = NSTextField(labelWithString: "No models - click Download")
            noModelLabel.frame = NSRect(x: controlX, y: y, width: 200, height: 24)
            noModelLabel.textColor = .secondaryLabelColor
            contentView.addSubview(noModelLabel)
        } else {
            let modelPopup = NSPopUpButton(frame: NSRect(x: controlX, y: y, width: 200, height: 24), pullsDown: false)
            modelPopup.tag = 2

            for (index, model) in installedModels.enumerated() {
                let title = "\(model.name) (\(model.size))"
                modelPopup.addItem(withTitle: title)
                // Use tag instead of representedObject to avoid memory issues
                modelPopup.lastItem?.tag = index
            }

            // Select current model
            for (index, model) in installedModels.enumerated() {
                if model.path == modelPath {
                    modelPopup.selectItem(at: index)
                    break
                }
            }

            modelPopup.target = self
            modelPopup.action = #selector(modelSelected(_:))
            contentView.addSubview(modelPopup)
        }

        let downloadBtn = NSButton(title: "Download...", target: self, action: #selector(downloadNewModel))
        downloadBtn.frame = NSRect(x: controlX + 210, y: y, width: 80, height: 24)
        contentView.addSubview(downloadBtn)

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

        // Models directory hint
        let hintLabel = NSTextField(labelWithString: "Models stored in: ~/.whisper-models/")
        hintLabel.frame = NSRect(x: 20, y: 15, width: 410, height: 20)
        hintLabel.font = NSFont.systemFont(ofSize: 10)
        hintLabel.textColor = .tertiaryLabelColor
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

    @objc func modelSelected(_ sender: NSPopUpButton) {
        let index = sender.selectedItem?.tag ?? 0
        let installedModels = WhisperModels.installedModels()
        if index >= 0 && index < installedModels.count {
            let path = installedModels[index].path
            modelPath = path
            checkModelExists()
            NSLog("Model changed to: \(path)")
        }
    }

    @objc func downloadNewModel() {
        // Create simple popup menu for model selection
        let menu = NSMenu(title: "Select Model")

        for (index, model) in WhisperModels.available.enumerated() {
            let item = NSMenuItem(title: "\(model.name) (\(model.size))", action: #selector(downloadModelAtIndex(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index

            // Add subtitle with pros/cons
            item.toolTip = "✓ \(model.pros)\n✗ \(model.cons)"
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Cancel", action: nil, keyEquivalent: ""))

        // Show menu at mouse location
        if let event = NSApp.currentEvent {
            NSMenu.popUpContextMenu(menu, with: event, for: settingsWindowController?.window?.contentView ?? statusItem.button!)
        }
    }

    @objc func downloadModelAtIndex(_ sender: NSMenuItem) {
        let index = sender.tag
        guard index >= 0 && index < WhisperModels.available.count else { return }
        let model = WhisperModels.available[index]
        NSLog("Starting download of \(model.name)")
        downloadModel(model)
    }

    @objc func browseModel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select Whisper model file (.bin)"

        if panel.runModal() == .OK, let url = panel.url {
            modelPath = url.path
            if let contentView = settingsWindowController?.window?.contentView {
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
        // First check for bundled whisper-cli
        if let bundlePath = Bundle.main.executablePath {
            let bundledCLI = (bundlePath as NSString).deletingLastPathComponent + "/whisper-cli"
            if FileManager.default.isExecutableFile(atPath: bundledCLI) {
                return bundledCLI
            }
        }

        // Fall back to system paths
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

        // Save current clipboard contents
        let savedItems = saveClipboard()

        // Set transcript to clipboard
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        NSLog("Transcribed: \(text)")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Simulate Cmd+V
            let source = CGEventSource(stateID: .hidSystemState)

            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
            keyDown?.flags = .maskCommand
            keyDown?.post(tap: .cghidEventTap)

            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
            keyUp?.flags = .maskCommand
            keyUp?.post(tap: .cghidEventTap)

            // Restore original clipboard after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.restoreClipboard(savedItems)
            }

            self.statusItem.button?.title = "🎤"
            self.updateStatus("Ready")
            if self.playSounds { NSSound(named: "Glass")?.play() }
        }
    }

    func saveClipboard() -> [[NSPasteboard.PasteboardType: Data]] {
        let pasteboard = NSPasteboard.general
        var savedItems: [[NSPasteboard.PasteboardType: Data]] = []

        for item in pasteboard.pasteboardItems ?? [] {
            var itemData: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    itemData[type] = data
                }
            }
            if !itemData.isEmpty {
                savedItems.append(itemData)
            }
        }
        return savedItems
    }

    func restoreClipboard(_ savedItems: [[NSPasteboard.PasteboardType: Data]]) {
        guard !savedItems.isEmpty else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        for itemData in savedItems {
            let item = NSPasteboardItem()
            for (type, data) in itemData {
                item.setData(data, forType: type)
            }
            pasteboard.writeObjects([item])
        }
    }
}

// MARK: - Main
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

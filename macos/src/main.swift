import Cocoa
import AVFoundation
import Carbon.HIToolbox
import ServiceManagement
import ApplicationServices
import Darwin

// MARK: - User Defaults Keys
struct Defaults {
    static let language = "whisperLanguage"
    static let modelPath = "whisperModelPath"
    static let playSounds = "playSounds"
    static let replacements = "customReplacements"
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
        Model(name: "Medium",
              filename: "ggml-medium.bin",
              size: "1.5 GB",
              url: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin",
              pros: "Good accuracy, handles accents well",
              cons: "Larger download, slower on older Macs"),
        Model(name: "Large v3 Turbo (Recommended)",
              filename: "ggml-large-v3-turbo.bin",
              size: "1.6 GB",
              url: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin",
              pros: "Best speed/accuracy ratio, fast like Medium, accurate like Large",
              cons: "Slightly larger than Medium"),
        Model(name: "Large v3",
              filename: "ggml-large-v3.bin",
              size: "3.1 GB",
              url: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin",
              pros: "Maximum accuracy for difficult audio",
              cons: "Very large, slow, minimal improvement over Turbo")
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
    static let autoDetect = "auto"

    static let codes: [String: String] = [
        "auto": "Auto-detect",
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
        return code == autoDetect || codes.keys.contains(code.lowercased())
    }

    static var sortedCodes: [(code: String, name: String)] {
        // Put Auto-detect first, then sort the rest alphabetically
        var result = [(code: "auto", name: "Auto-detect")]
        result += codes.filter { $0.key != "auto" }.sorted { $0.value < $1.value }.map { (code: $0.key, name: $0.value) }
        return result
    }
}

// MARK: - Whisper Server (warm, preloaded-model backend)
// Keeps a whisper-server child process alive with the model already loaded, so
// each dictation is a fast local HTTP call (~0.5s) instead of a multi-second
// model + Metal reload on every utterance (what plain whisper-cli does).
final class WhisperServer {
    private let serverPath: String
    private let modelPath: String
    private let threads: Int
    private var process: Process?
    private var stopping = false
    private(set) var port: Int = 0
    private(set) var isReady = false

    init(serverPath: String, modelPath: String, threads: Int) {
        self.serverPath = serverPath
        self.modelPath = modelPath
        self.threads = threads
    }

    func start(onReady: @escaping (Bool) -> Void) {
        port = WhisperServer.findFreePort()
        let task = Process()
        task.executableURL = URL(fileURLWithPath: serverPath)
        task.arguments = [
            "-m", modelPath,
            "--host", "127.0.0.1",
            "--port", String(port),
            "-t", String(threads),
            "-nt",   // no timestamps -> plain text response
            "-sns",  // suppress non-speech tokens -> fewer hallucinations
        ]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        task.terminationHandler = { [weak self] _ in self?.isReady = false }
        do {
            try task.run()
            process = task
        } catch {
            NSLog("WhisperServer: failed to launch: \(error)")
            onReady(false)
            return
        }
        // Model load can take ~10s (incl. Metal init); poll the port off-thread.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let deadline = Date().addingTimeInterval(120)
            while Date() < deadline {
                if self.stopping || !(self.process?.isRunning ?? false) { break }
                if WhisperServer.canConnect(port: self.port) {
                    self.isReady = true
                    onReady(true)
                    return
                }
                Thread.sleep(forTimeInterval: 0.3)
            }
            onReady(false)
        }
    }

    func stop() {
        stopping = true
        isReady = false
        process?.terminationHandler = nil
        process?.terminate()
        process = nil
    }

    // Synchronous transcription via the warm server. Call OFF the main thread.
    func transcribe(wavPath: String, language: String, prompt: String?) -> String? {
        guard isReady,
              let url = URL(string: "http://127.0.0.1:\(port)/inference"),
              let wavData = try? Data(contentsOf: URL(fileURLWithPath: wavPath)) else { return nil }

        let boundary = "----WhisperDictate\(UInt32.random(in: 0 ... .max))"
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 120

        var body = Data()
        let nl = "\r\n"
        func raw(_ s: String) { body.append(s.data(using: .utf8)!) }
        // audio file part
        raw("--\(boundary)\(nl)")
        raw("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\(nl)")
        raw("Content-Type: audio/wav\(nl)\(nl)")
        body.append(wavData)
        raw(nl)
        // text fields
        func field(_ name: String, _ value: String) {
            raw("--\(boundary)\(nl)")
            raw("Content-Disposition: form-data; name=\"\(name)\"\(nl)\(nl)")
            raw("\(value)\(nl)")
        }
        field("response_format", "json")
        field("temperature", "0")
        if language.lowercased() != SupportedLanguages.autoDetect { field("language", language.lowercased()) }
        if let prompt = prompt, !prompt.isEmpty { field("prompt", prompt) }
        raw("--\(boundary)--\(nl)")
        req.httpBody = body

        let sem = DispatchSemaphore(value: 0)
        var result: String?
        URLSession.shared.dataTask(with: req) { data, _, error in
            defer { sem.signal() }
            if let error = error { NSLog("WhisperServer: request error: \(error)"); return }
            guard let data = data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let text = obj["text"] as? String else { return }
            result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }.resume()
        sem.wait()
        return result
    }

    // MARK: socket helpers (find a free loopback port + readiness probe)
    static func findFreePort() -> Int {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        if fd < 0 { return 8123 }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = 0
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else { return 8123 }
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &len)
            }
        }
        return Int(UInt16(bigEndian: addr.sin_port))
    }

    static func canConnect(port: Int) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        if fd < 0 { return false }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(port)).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let r = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return r == 0
    }
}

// MARK: - Recording HUD (live mic level + silence warning)
// A small floating, non-interactive panel shown while recording. Doubles as a
// diagnostic: if the input stays silent it flags "no input" — exactly the
// failure that silently produced empty recordings + whisper hallucinations.
final class MeterView: NSView {
    private var level: CGFloat = 0
    private var silent = false

    func set(level: CGFloat, silent: Bool) {
        self.level = max(0, min(1, level))
        self.silent = silent
        needsDisplay = true
    }
    func reset() { level = 0; silent = false; needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        let bg = NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12)
        NSColor(calibratedWhite: 0.10, alpha: 0.93).setFill()
        bg.fill()

        let label = silent ? "🎤 Nincs hangbemenet?" : "🎤 Felvétel…"
        label.draw(at: NSPoint(x: 16, y: bounds.height - 26), withAttributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: silent ? NSColor.systemRed : NSColor.white
        ])

        let segs = 20
        let margin: CGFloat = 16, gap: CGFloat = 3, segH: CGFloat = 14, y: CGFloat = 14
        let segW = (bounds.width - margin * 2 - gap * CGFloat(segs - 1)) / CGFloat(segs)
        let lit = Int((level * CGFloat(segs)).rounded())
        for i in 0..<segs {
            let rect = NSRect(x: margin + CGFloat(i) * (segW + gap), y: y, width: segW, height: segH)
            let path = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
            if i < lit {
                let frac = CGFloat(i) / CGFloat(segs)
                (silent ? NSColor.systemRed
                        : frac > 0.85 ? .systemRed
                        : frac > 0.6 ? .systemYellow : .systemGreen).setFill()
            } else {
                NSColor(calibratedWhite: 1, alpha: 0.12).setFill()
            }
            path.fill()
        }
    }
}

final class RecordingHUD {
    private var window: NSWindow?
    private let meter = MeterView(frame: NSRect(x: 0, y: 0, width: 260, height: 72))

    func show() {
        if window == nil {
            let w = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 260, height: 72),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = true
            w.level = .statusBar
            w.ignoresMouseEvents = true
            w.isFloatingPanel = true
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            w.contentView = meter
            window = w
        }
        if let screen = NSScreen.main, let window = window {
            let vf = screen.visibleFrame
            window.setFrameOrigin(NSPoint(x: vf.midX - window.frame.width / 2, y: vf.minY + 120))
        }
        meter.reset()
        window?.orderFrontRegardless()
    }

    func update(level: CGFloat, silent: Bool) { meter.set(level: level, silent: silent) }
    func hide() { window?.orderOut(nil) }
}

// MARK: - App Delegate
class AppDelegate: NSObject, NSApplicationDelegate, URLSessionDownloadDelegate, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate, NSWindowDelegate {
    var statusItem: NSStatusItem!
    var audioRecorder: AVAudioRecorder?
    var isRecording = false
    var settingsWindowController: NSWindowController?
    var whisperServer: WhisperServer?
    let recordingHUD = RecordingHUD()
    var meterTimer: Timer?
    var silenceStart: Date?
    weak var dictTable: NSTableView?

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

    // Custom dictionary: ordered list of ["from": recognised, "to": replacement].
    var replacements: [[String: String]] {
        get { (UserDefaults.standard.array(forKey: Defaults.replacements) as? [[String: String]]) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: Defaults.replacements) }
    }

    // Whisper initial prompt built from the desired ("to") terms, to bias
    // recognition toward the user's names/jargon. Returns nil if empty.
    func customPrompt() -> String? {
        let terms = replacements.compactMap { $0["to"] }
            .map { $0.replacingOccurrences(of: "\\n", with: " ") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return terms.isEmpty ? nil : terms.joined(separator: ", ")
    }

    // Apply the dictionary find/replace pairs to a transcript. "\n" in a
    // replacement becomes a real newline (e.g. spoken-command → line break).
    func applyReplacements(_ text: String) -> String {
        var result = text
        for pair in replacements {
            guard let from = pair["from"], !from.isEmpty else { continue }
            let to = (pair["to"] ?? "").replacingOccurrences(of: "\\n", with: "\n")
            result = result.replacingOccurrences(of: from, with: to, options: [.caseInsensitive])
        }
        return result
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        registerHotkey()
        requestMicrophonePermission()

        // Start warming the model server BEFORE the (blocking) accessibility
        // prompt, so the multi-second model load overlaps with the user
        // granting permissions instead of running after it.
        if !hasAnyModel() {
            showFirstRunWizard()
        } else {
            checkModelExists()
            startWhisperServer()
        }

        checkAccessibilityPermission()

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
            startWhisperServer()
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
        whisperServer?.stop()
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
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 540),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "WhisperDictate Settings"
        window.center()
        window.delegate = self

        let contentView = NSView(frame: window.contentView!.bounds)

        var y: CGFloat = 498
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

        // Custom dictionary (recognised -> replacement)
        let dictLabel = NSTextField(labelWithString: "Szótár (felismert → csere):")
        dictLabel.frame = NSRect(x: 20, y: 304, width: 300, height: 20)
        contentView.addSubview(dictLabel)

        let scroll = NSScrollView(frame: NSRect(x: 20, y: 104, width: 410, height: 192))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let table = NSTableView(frame: scroll.bounds)
        table.usesAlternatingRowBackgroundColors = true
        table.rowHeight = 22
        let colFrom = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("from"))
        colFrom.title = "Felismert"; colFrom.width = 195; colFrom.isEditable = true
        let colTo = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("to"))
        colTo.title = "Helyette"; colTo.width = 195
        table.addTableColumn(colFrom)
        table.addTableColumn(colTo)
        table.dataSource = self
        table.delegate = self
        scroll.documentView = table
        contentView.addSubview(scroll)
        dictTable = table

        let addBtn = NSButton(title: "+", target: self, action: #selector(addReplacement))
        addBtn.frame = NSRect(x: 20, y: 70, width: 34, height: 26)
        addBtn.bezelStyle = .rounded
        contentView.addSubview(addBtn)
        let delBtn = NSButton(title: "–", target: self, action: #selector(removeReplacement))
        delBtn.frame = NSRect(x: 56, y: 70, width: 34, height: 26)
        delBtn.bezelStyle = .rounded
        contentView.addSubview(delBtn)

        let dictHint = NSTextField(labelWithString: "A „Helyette” oszlop a felismerést is pontosítja. \\n = új sor.")
        dictHint.frame = NSRect(x: 100, y: 74, width: 330, height: 18)
        dictHint.font = NSFont.systemFont(ofSize: 10)
        dictHint.textColor = .tertiaryLabelColor
        contentView.addSubview(dictHint)

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
            startWhisperServer()
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

    // MARK: - Custom dictionary table (view-based, editable text fields)
    func numberOfRows(in tableView: NSTableView) -> Int { replacements.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let column = tableColumn, row < replacements.count else { return nil }
        let id = column.identifier
        let field: NSTextField
        if let reused = tableView.makeView(withIdentifier: id, owner: self) as? NSTextField {
            field = reused
        } else {
            field = NSTextField()
            field.identifier = id
            field.isBordered = false
            field.drawsBackground = false
            field.isEditable = true
            field.isSelectable = true
            field.font = NSFont.systemFont(ofSize: 12)
            field.lineBreakMode = .byTruncatingTail
            field.delegate = self
            field.placeholderString = id.rawValue == "from" ? "felismert szó" : "csere (\\n = új sor)"
        }
        field.stringValue = replacements[row][id.rawValue] ?? ""
        return field
    }

    // Commit an edited cell back into the model (fires on Enter, Tab, focus loss).
    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, let table = dictTable else { return }
        let row = table.row(for: field), col = table.column(for: field)
        guard row >= 0, row < replacements.count, col >= 0, col < table.tableColumns.count else { return }
        let id = table.tableColumns[col].identifier.rawValue
        var rows = replacements
        rows[row][id] = field.stringValue
        replacements = rows
    }

    @objc func addReplacement() {
        pruneEmptyReplacements()
        var rows = replacements
        rows.append(["from": "", "to": ""])
        replacements = rows
        dictTable?.reloadData()
        dictTable?.editColumn(0, row: rows.count - 1, with: nil, select: true)
    }

    @objc func removeReplacement() {
        guard let table = dictTable, table.selectedRow >= 0, table.selectedRow < replacements.count else { return }
        var rows = replacements
        rows.remove(at: table.selectedRow)
        replacements = rows
        table.reloadData()
    }

    // Drop rows where both columns are blank so empty rows aren't persisted.
    func pruneEmptyReplacements() {
        let cleaned = replacements.filter {
            !(($0["from"] ?? "").trimmingCharacters(in: .whitespaces).isEmpty
              && ($0["to"] ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
        }
        if cleaned.count != replacements.count { replacements = cleaned }
    }

    func windowWillClose(_ notification: Notification) {
        pruneEmptyReplacements()
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
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()
            isRecording = true
            statusItem.button?.title = "🔴"
            updateStatus("Recording...")
            if playSounds { NSSound(named: "Tink")?.play() }
            NSLog("Recording started")
            startMeter()
        } catch {
            NSLog("Recording failed: \(error)")
            if playSounds { NSSound(named: "Basso")?.play() }
        }
    }

    // MARK: - Live mic meter (HUD)
    func startMeter() {
        silenceStart = nil
        recordingHUD.show()
        meterTimer?.invalidate()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.updateMeter()
        }
    }

    func stopMeter() {
        meterTimer?.invalidate()
        meterTimer = nil
        silenceStart = nil
        recordingHUD.hide()
    }

    func updateMeter() {
        guard isRecording, let recorder = audioRecorder else { return }
        recorder.updateMeters()
        let avg = recorder.averagePower(forChannel: 0)   // dBFS, ~-160...0
        let peak = recorder.peakPower(forChannel: 0)
        let level = max(0, min(1, CGFloat((avg + 50) / 50)))

        // Flag "no input" if the peak stays at silence for over ~1.2s.
        if peak < -50 {
            if silenceStart == nil { silenceStart = Date() }
        } else {
            silenceStart = nil
        }
        let silent = silenceStart.map { Date().timeIntervalSince($0) > 1.2 } ?? false
        recordingHUD.update(level: level, silent: silent)
    }

    func stopRecordingAndTranscribe() {
        audioRecorder?.stop()
        isRecording = false
        stopMeter()
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

    func findWhisperServer() -> String? {
        if let bundlePath = Bundle.main.executablePath {
            let bundled = (bundlePath as NSString).deletingLastPathComponent + "/whisper-server"
            if FileManager.default.isExecutableFile(atPath: bundled) { return bundled }
        }
        let paths = [
            "/opt/homebrew/bin/whisper-server",
            "/usr/local/bin/whisper-server",
            "/opt/local/bin/whisper-server",
            NSHomeDirectory() + "/bin/whisper-server"
        ]
        for path in paths where FileManager.default.isExecutableFile(atPath: path) { return path }
        return nil
    }

    // (Re)start the warm whisper-server for the current model. Falls back to
    // per-call whisper-cli if the server binary is missing or fails to come up.
    func startWhisperServer() {
        whisperServer?.stop()
        whisperServer = nil

        guard let serverPath = findWhisperServer() else {
            NSLog("whisper-server not found — using per-call whisper-cli")
            return
        }
        guard isValidModelPath(modelPath).valid else { return }

        statusItem.button?.title = "⏳"
        updateStatus("Loading model…")

        let threads = min(8, max(2, ProcessInfo.processInfo.activeProcessorCount - 2))
        let server = WhisperServer(serverPath: serverPath, modelPath: modelPath, threads: threads)
        whisperServer = server
        server.start { [weak self] ok in
            DispatchQueue.main.async {
                guard let self = self, self.whisperServer === server else { return }
                self.statusItem.button?.title = "🎤"
                if ok {
                    self.updateStatus("Ready")
                    NSLog("whisper-server ready on port \(server.port)")
                } else {
                    self.updateStatus("Ready (CLI fallback)")
                    self.whisperServer = nil
                    NSLog("whisper-server failed to start — falling back to whisper-cli")
                }
            }
        }
    }

    // MARK: - Transcription
    func transcribe() {
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

        // Prefer the warm server (~0.5s); fall back to a per-call whisper-cli spawn.
        let prompt = customPrompt()
        let result: String?
        if let server = whisperServer, server.isReady {
            result = server.transcribe(wavPath: audioFilePath, language: language, prompt: prompt)
        } else {
            result = transcribeWithCLI(prompt: prompt)
        }

        self.cleanupAudioFile()

        let finalText = result.map { applyReplacements($0) }

        DispatchQueue.main.async {
            if let finalText = finalText, !finalText.isEmpty {
                self.pasteText(finalText)
            } else {
                self.statusItem.button?.title = "🎤"
                self.updateStatus("Ready")
                if self.playSounds { NSSound(named: "Basso")?.play() }
                NSLog("No speech recognized")
            }
        }
    }

    // Per-call transcription via whisper-cli (reloads the model every time).
    // Fallback for when the warm server is unavailable.
    func transcribeWithCLI(prompt: String? = nil) -> String? {
        guard let whisperPath = findWhisperCLI() else {
            DispatchQueue.main.async {
                self.statusItem.button?.title = "🎤"
                self.updateStatus("⚠️ whisper-cli not found")
                if self.playSounds { NSSound(named: "Basso")?.play() }
                NSLog("whisper-cli not found in PATH")
            }
            return nil
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: whisperPath)
        var args = ["-m", modelPath]
        if language.lowercased() != SupportedLanguages.autoDetect {
            args += ["-l", language.lowercased()]
        }
        if let prompt = prompt, !prompt.isEmpty { args += ["--prompt", prompt] }
        args += ["-f", audioFilePath]
        task.arguments = args

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            var result = ""
            for line in output.components(separatedBy: "\n") where line.hasPrefix("[") {
                if let range = line.range(of: "]") {
                    result += String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces) + " "
                }
            }
            return result.trimmingCharacters(in: .whitespaces)
        } catch {
            NSLog("Transcription failed: \(error)")
            return nil
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
            // If clipboard was empty, clear it (don't leave transcript)
            // If clipboard had content, restore it
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if savedItems.isEmpty {
                    NSPasteboard.general.clearContents()
                } else {
                    self.restoreClipboard(savedItems)
                }
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

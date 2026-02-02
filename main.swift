import Cocoa
import AVFoundation
import Carbon.HIToolbox

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var audioRecorder: AVAudioRecorder?
    var isRecording = false
    let audioFilePath = "/tmp/whisper-dictate.wav"
    let whisperModel = NSHomeDirectory() + "/.whisper-models/ggml-medium.bin"

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create menu bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🎤"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Toggle Recording (⌃⌥D)", action: #selector(toggleRecording), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu

        // Register global hotkey (Control + Option + D)
        registerHotkey()

        // Request microphone permission
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            if !granted {
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "Microphone access required"
                    alert.informativeText = "Please enable microphone access in System Settings → Privacy & Security → Microphone"
                    alert.runModal()
                }
            }
        }

        NSLog("WhisperDictate started. Press ⌃⌥D to toggle recording.")
    }

    func registerHotkey() {
        // Register Control + Option + D
        var hotKeyRef: EventHotKeyRef?
        var gMyHotKeyID = EventHotKeyID()
        gMyHotKeyID.signature = OSType(0x57485044) // "WHPD"
        gMyHotKeyID.id = 1

        // D = 2, Control = 0x1000, Option = 0x0800
        let modifiers: UInt32 = UInt32(controlKey | optionKey)
        let keyCode: UInt32 = 2 // D key

        RegisterEventHotKey(keyCode, modifiers, gMyHotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)

        // Install event handler
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { (_, event, _) -> OSStatus in
            let appDelegate = NSApplication.shared.delegate as! AppDelegate
            DispatchQueue.main.async {
                appDelegate.toggleRecording()
            }
            return noErr
        }, 1, &eventType, nil, nil)
    }

    @objc func toggleRecording() {
        if isRecording {
            stopRecordingAndTranscribe()
        } else {
            startRecording()
        }
    }

    func startRecording() {
        let audioURL = URL(fileURLWithPath: audioFilePath)

        // Remove old file
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
            NSSound(named: "Tink")?.play()
            NSLog("Recording started")
        } catch {
            NSLog("Recording failed: \(error)")
            NSSound(named: "Basso")?.play()
        }
    }

    func stopRecordingAndTranscribe() {
        audioRecorder?.stop()
        isRecording = false
        statusItem.button?.title = "⏳"
        NSSound(named: "Pop")?.play()
        NSLog("Recording stopped, transcribing...")

        DispatchQueue.global(qos: .userInitiated).async {
            self.transcribe()
        }
    }

    func transcribe() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/whisper-cli")
        task.arguments = ["-m", whisperModel, "-l", "hu", "-f", audioFilePath]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            // Parse output - extract text from lines like "[00:00:00.000 --> 00:00:03.000]   Hello world"
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

            DispatchQueue.main.async {
                if !result.isEmpty {
                    self.pasteText(result)
                } else {
                    self.statusItem.button?.title = "🎤"
                    NSSound(named: "Basso")?.play()
                    NSLog("No speech recognized")
                }
            }
        } catch {
            DispatchQueue.main.async {
                self.statusItem.button?.title = "🎤"
                NSSound(named: "Basso")?.play()
                NSLog("Transcription failed: \(error)")
            }
        }
    }

    func pasteText(_ text: String) {
        // Copy to clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        NSLog("Transcribed: \(text)")

        // Simulate Cmd+V
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let source = CGEventSource(stateID: .hidSystemState)

            // Key down
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true) // V key
            keyDown?.flags = .maskCommand
            keyDown?.post(tap: .cghidEventTap)

            // Key up
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
            keyUp?.flags = .maskCommand
            keyUp?.post(tap: .cghidEventTap)

            self.statusItem.button?.title = "🎤"
            NSSound(named: "Glass")?.play()
        }
    }
}

// Main
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // Menu bar only, no dock icon
app.run()

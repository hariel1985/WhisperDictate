# WhisperDictate

A simple menu bar app for voice dictation using OpenAI Whisper (local, offline).

## Platforms

| Platform | Language | Status |
|----------|----------|--------|
| macOS | Swift | ✅ Ready |
| Linux | Rust | 🔜 Planned |
| Windows | C# | 🔜 Planned |

## macOS

### Features

- 🎤 Global hotkey (⌃⌥D) to start/stop recording
- 🔒 Fully offline - uses local Whisper model
- ⚡ Automatic paste into any focused app
- ⚙️ Settings window (language, model path, sounds)
- 🚀 Launch at login support

### Requirements

- macOS 13.0+
- Apple Silicon Mac (M1/M2/M3)
- whisper-cpp (`brew install whisper-cpp`)
- Whisper model file

### Installation

#### 1. Install whisper-cpp

```bash
brew install whisper-cpp
```

#### 2. Download Whisper model

```bash
mkdir -p ~/.whisper-models
curl -L -o ~/.whisper-models/ggml-medium.bin \
  "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin"
```

#### 3. Build and install

```bash
cd macos
make install
```

This compiles the app and installs it to `/Applications/WhisperDictate.app`.

### Usage

1. Launch WhisperDictate from Applications
2. Look for the 🎤 icon in your menu bar
3. Press **⌃⌥D** (Control + Option + D) to start recording
4. Speak (icon changes to 🔴)
5. Press **⌃⌥D** again to stop and transcribe
6. Text is automatically pasted where your cursor is

### Settings

Click the menu bar icon → Settings to configure:
- **Language**: Two-letter code (hu, en, de, fr, es...)
- **Model Path**: Path to your Whisper model file
- **Sound feedback**: Toggle audio feedback on/off
- **Launch at login**: Start automatically when you log in

### Audio Feedback

- 🔔 **Tink** - Recording started
- 🔔 **Pop** - Recording stopped, processing
- 🔔 **Glass** - Success, text pasted
- 🔔 **Basso** - Error

### Permissions

Grant these in System Settings → Privacy & Security:
- **Microphone** - for recording
- **Accessibility** - for auto-paste

### Build Commands

```bash
make build    # Compile the app
make install  # Install to /Applications
make run      # Build and run
make dmg      # Create distributable DMG
make clean    # Remove build artifacts
```

## License

MIT License

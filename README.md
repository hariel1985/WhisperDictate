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
- Apple Silicon (M1/M2/M3) or Intel Mac
- whisper-cpp (`brew install whisper-cpp`)
- Whisper model file

### Quick Install (Download)

1. Download the latest DMG from [Releases](https://github.com/hariel1985/WhisperDictate/releases)
2. Open the DMG and drag WhisperDictate to Applications
3. Install dependencies:

```bash
# Install whisper-cpp
brew install whisper-cpp

# Download Whisper model
mkdir -p ~/.whisper-models
curl -L -o ~/.whisper-models/ggml-medium.bin \
  "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin"
```

4. Launch WhisperDictate and grant permissions (Microphone + Accessibility)

### Build from Source

If you prefer to build the app yourself:

```bash
# Clone the repository
git clone https://github.com/hariel1985/WhisperDictate.git
cd WhisperDictate/macos

# Build and install to /Applications
make install

# Or just build without installing
make build
```

#### Build Commands

| Command | Description |
|---------|-------------|
| `make build` | Compile the app |
| `make install` | Build and install to /Applications |
| `make run` | Build and run |
| `make dmg` | Create distributable DMG |
| `make clean` | Remove build artifacts |

### Usage

1. Launch WhisperDictate from Applications
2. Look for the 🎤 icon in your menu bar
3. Press **⌃⌥D** (Control + Option + D) to start recording
4. Speak (icon changes to 🔴)
5. Press **⌃⌥D** again to stop and transcribe
6. Text is automatically pasted where your cursor is

### Settings

Click the menu bar icon → Settings to configure:
- **Language**: 31 supported languages (dropdown)
- **Model Path**: Path to your Whisper model file
- **Sound feedback**: Toggle audio feedback on/off
- **Launch at login**: Start automatically when you log in

### Whisper Models

| Model | Size | Speed | Accuracy | Download |
|-------|------|-------|----------|----------|
| tiny | 75 MB | Fastest | Basic | [Download](https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin) |
| base | 142 MB | Fast | Good | [Download](https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin) |
| small | 466 MB | Medium | Better | [Download](https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin) |
| medium | 1.5 GB | Slow | Best | [Download](https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin) |

For Intel Macs, consider using `small` or `base` models for faster transcription.

### Audio Feedback

- 🔔 **Tink** - Recording started
- 🔔 **Pop** - Recording stopped, processing
- 🔔 **Glass** - Success, text pasted
- 🔔 **Basso** - Error

### Permissions

Grant these in System Settings → Privacy & Security:
- **Microphone** - for recording
- **Accessibility** - for auto-paste

> **Note**: After reinstalling or updating, you may need to remove and re-add the app in Accessibility settings.

## License

MIT License

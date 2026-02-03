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
- 📋 Clipboard preservation - your copied content is restored after paste
- ⚙️ Settings window with model selection dropdown
- 📥 Built-in model downloader with progress indicator
- 🚀 Launch at login support
- 🔊 Sound feedback (optional)
- 📦 Self-contained - whisper-cli bundled in app

### Requirements

- macOS 13.0+
- Apple Silicon (M1/M2/M3) or Intel Mac

### Quick Install (Download)

1. Download the latest DMG from [Releases](https://github.com/hariel1985/WhisperDictate/releases)
2. Open the DMG and drag WhisperDictate to Applications
3. Launch WhisperDictate
4. On first run, select and download a Whisper model
5. Grant permissions (Microphone + Accessibility)

### Build from Source

```bash
# Clone the repository
git clone https://github.com/hariel1985/WhisperDictate.git
cd WhisperDictate/macos

# Install whisper-cpp (required for bundling)
brew install whisper-cpp

# Build and install to /Applications
make install
```

#### Build Commands

| Command | Description |
|---------|-------------|
| `make build` | Compile the app and bundle whisper-cli |
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
- **Model**: Select from installed models or download new ones
- **Sound feedback**: Toggle audio feedback on/off
- **Launch at login**: Start automatically when you log in

### Whisper Models

Download models directly from the app or manually:

| Model | Size | Speed | Accuracy | Best For |
|-------|------|-------|----------|----------|
| Tiny | 75 MB | ~1 sec | Basic | Quick tests, simple phrases |
| Base | 142 MB | ~2 sec | Good | Clear speech, quiet environment |
| Small | 466 MB | ~3 sec | Better | General use, some accents |
| Medium | 1.5 GB | ~5 sec | Great | Accents, noisy audio |
| Large v3 Turbo | 1.6 GB | ~4 sec | Best | **Recommended** - fast like Medium, accurate like Large |
| Large v3 | 3.1 GB | ~8 sec | Maximum | Difficult audio, max accuracy |

Models are stored in `~/.whisper-models/`

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

## Security

- All processing is done locally - no data leaves your device
- Audio files are stored in private temp directory and deleted after transcription
- Input validation prevents command injection
- No network access except for optional model downloads from Hugging Face

## License

MIT License

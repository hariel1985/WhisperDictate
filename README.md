# WhisperDictate

A simple menu bar app for voice dictation using OpenAI Whisper (local, offline).

## Platforms

| Platform | Language | Status |
|----------|----------|--------|
| macOS | Swift | ✅ Ready |
| Linux | Rust | 🔜 Planned |
| Windows | C# | 🔜 Planned |

## macOS

### What's new in 1.3.0

- ⚡ **Warm transcription server** — the Whisper model stays loaded in a background `whisper-server`, so each dictation is a fast local call (~0.5s) instead of reloading the 1.5–1.6 GB model on every utterance
- 📊 **Live mic-level HUD** while recording, which warns ("No audio input?") if the microphone stays silent
- 📖 **Custom dictionary** — an editable *Heard → Replacement* table that fixes names/jargon in the transcript and also biases recognition

### Features

- 🎤 Global hotkey (⌃⌥D) to start/stop recording
- ⚡ Fast transcription via a warm whisper-server (model stays loaded — no per-dictation reload), with automatic fallback to `whisper-cli`
- 📊 Live mic-level meter while recording, with a "no audio input" warning
- 📖 Custom dictionary (heard → replacement) that also biases recognition
- 🔒 Fully offline - uses local Whisper model
- ⌨️ Automatic paste into any focused app
- 📋 Clipboard preservation - your copied content is restored after paste
- ⚙️ Settings window with model selection dropdown
- 📥 Built-in model downloader with progress indicator
- 🚀 Launch at login support
- 🔊 Sound feedback (optional)
- 📦 Self-contained - whisper-cli and whisper-server bundled in the app

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
- **Language**: Auto-detect or 31 supported languages
- **Model**: Select from installed models or download new ones
- **Dictionary**: Add *Heard → Replacement* pairs to fix names/jargon (use `\n` for a newline); the replacement terms also improve recognition
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

> With the warm server (1.3.0+), the selected model loads once at startup (a few seconds); after that each dictation skips the reload, so the speeds above are roughly the per-dictation transcription time.

### Audio Feedback

- 🔔 **Tink** - Recording started
- 🔔 **Pop** - Recording stopped, processing
- 🔔 **Glass** - Success, text pasted
- 🔔 **Basso** - Error

### Permissions

Grant these in System Settings → Privacy & Security:

| Permission | Why it's needed |
|------------|-----------------|
| **Microphone** | To record your voice for transcription |
| **Accessibility** | To simulate ⌘V keystroke and paste text into any app. macOS requires this permission for apps that send keyboard events to other applications. |

> **Note**: After reinstalling or updating, you may need to remove and re-add the app in Accessibility settings.

## Security

- All processing is done locally - no data leaves your device
- The bundled `whisper-server` is bound to `127.0.0.1` (loopback only) and is never exposed on the network
- Audio files are stored in private temp directory and deleted after transcription
- Clipboard is cleared after paste (transcript doesn't remain accessible)
- Original clipboard content is preserved and restored after paste
- Input validation prevents command injection
- No network access except for optional model downloads from Hugging Face

## License

MIT License

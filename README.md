# WhisperDictate

A simple macOS menu bar app for voice dictation using OpenAI Whisper (local, offline).

## Features

- 🎤 Global hotkey (⌃⌥D) to start/stop recording
- 🔒 Fully offline - uses local Whisper model
- ⚡ Automatic paste into any app
- 🇭🇺 Hungarian language support (configurable)

## Requirements

- macOS 13.0+
- Apple Silicon Mac (M1/M2/M3)
- whisper-cpp (`brew install whisper-cpp`)
- Whisper model file

## Installation

### 1. Install whisper-cpp

```bash
brew install whisper-cpp sox
```

### 2. Download Whisper model

```bash
mkdir -p ~/.whisper-models
curl -L -o ~/.whisper-models/ggml-medium.bin \
  "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin"
```

### 3. Build WhisperDictate

```bash
git clone https://github.com/YourUsername/WhisperDictate.git
cd WhisperDictate
swiftc -o WhisperDictate main.swift \
    -framework Cocoa \
    -framework AVFoundation \
    -framework Carbon \
    -framework CoreGraphics
```

### 4. Run

```bash
./WhisperDictate
```

Or copy to your bin folder:

```bash
cp WhisperDictate ~/bin/
~/bin/WhisperDictate &
```

## Usage

1. Look for the 🎤 icon in your menu bar
2. Press **⌃⌥D** (Control + Option + D) to start recording
3. Speak (icon changes to 🔴)
4. Press **⌃⌥D** again to stop and transcribe
5. Text is automatically pasted where your cursor is

## Audio Feedback

- 🔔 **Tink** - Recording started
- 🔔 **Pop** - Recording stopped, processing
- 🔔 **Glass** - Success, text pasted
- 🔔 **Basso** - Error

## Permissions

The app needs:
- **Microphone** access (System Settings → Privacy & Security → Microphone)
- **Accessibility** access for auto-paste (System Settings → Privacy & Security → Accessibility)

## Configuration

Edit `main.swift` to change:
- Language: Change `"-l", "hu"` to your language code (e.g., `"en"`, `"de"`)
- Hotkey: Modify `registerHotkey()` function
- Model: Change `whisperModel` path for different model sizes

## License

MIT License

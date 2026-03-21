# Crack 🚪

Turn your MacBook into a squeaky door. Crack monitors your lid angle sensor and plays a creak sound whenever you move the lid — with pitch varying based on how fast you move it.

## Features

- **Real-time lid detection** — Uses the built-in HID lid angle sensor at 60fps
- **Variable pitch** — Sound playback speed scales with lid movement velocity
- **Menu bar app** — No windows, just a clean menu bar icon
- **18 built-in sounds** — Cracks, creaks, voice effects, synth sounds
- **Volume control** — Adjustable via slider in the menu

## Download

Get the latest release from the [releases page](https://github.com/ronreiter/crack/releases/latest) or visit the [website](https://ronreiter.github.io/crack).

## Building from Source

### Requirements
- macOS 13.0+
- Xcode 15+
- [Task](https://taskfile.dev) (optional, for build automation)

### Quick Build
```bash
task run
```

### Full Release Build (signed + notarized)
```bash
task release
```

### Manual Build
```bash
xcodebuild -project Crack.xcodeproj -scheme Crack -configuration Release build
```

## How It Works

Crack reads the MacBook lid angle sensor via IOKit HID at 60 times per second. When it detects the angle changing (threshold: >0.001°), it plays a looping audio sample through AVAudioEngine with an AVAudioUnitVarispeed node. The varispeed rate is smoothly interpolated based on the angular velocity of the lid movement, creating a natural squeaky door effect.

## License

MIT

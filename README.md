# ShoveIt

Control where macOS notification banners appear on your screen. Move them to any of 9 positions — per-display on multi-monitor setups.

Based on [PingPlace](https://github.com/NotWadeGrimridge/PingPlace) by Wade Grimridge, with multi-monitor support, per-display positioning, and macOS Tahoe (26.3+) compatibility.

## Install

### Homebrew

```sh
brew install --cask jaysonrawlins/tap/shoveit
```

### Manual

Download `ShoveIt.app.tar.gz` from [Releases](https://github.com/JaysonRawlins/ShoveIt/releases), extract, and move to `/Applications`.

## Usage

ShoveIt runs as a menu bar app. Click the icon to choose a notification position:

- **Top Left / Top Middle / Top Right**
- **Middle Left / Middle / Middle Right**
- **Bottom Left / Bottom Middle / Bottom Right**

`Top Right` is the macOS default — selecting it effectively disables repositioning for that display.

### Multi-Monitor

When multiple displays are connected, a **Display** selector appears at the top of the menu. Each display has independent position settings — set `Top Middle` on your main monitor and `Bottom Right` on your secondary, for example.

### Launch at Login

Enable via the menu to create a LaunchAgent that starts ShoveIt automatically.

### Hide Menu Bar Icon

If you prefer a cleaner menu bar, hide the icon. Re-launch ShoveIt to show it again.

## Requirements

- macOS 14.0 (Sonoma) or later
- Accessibility permission (prompted on first launch)

## Build from Source

```sh
git clone https://github.com/JaysonRawlins/ShoveIt.git
cd ShoveIt
make test    # run unit tests
make build   # build universal binary (arm64 + x86_64)
make run     # build and launch
```

## Credits

- Original concept and implementation by [Wade Grimridge](https://github.com/NotWadeGrimridge) (PingPlace)
- Multi-monitor support, per-display positions, and macOS Tahoe compatibility by [Jayson Rawlins](https://github.com/JaysonRawlins)

## License

MIT

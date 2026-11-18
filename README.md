# menubar_tint

<img width="1408" height="881" alt="screen" src="https://github.com/user-attachments/assets/30930d9c-11e7-47d4-aebf-cb6ccbe1f10b" />


A lightweight macOS command-line utility and native Swift overlay that tints the menu bar's white text and icons with any arbitrary hexadecimal color (`#RRGGBB`), without replacing the native macOS menu bar.

## How It Works

macOS does not expose a public setting or API to customize the color of menu bar text and icons directly. This tool solves that by placing a borderless, click-through (`ignoresMouseEvents = true`) `NSWindow` overlay directly over the menu bar on all connected displays:

- **Adaptive Blend Modes (`CABackdropLayer` + `CAFilter`):** Uses `multiplyBlendMode` in dark setups (tinting white text/icons while keeping pure black untouched) and `screenBlendMode` in light setups (tinting black text/icons while keeping pure white untouched).
- **Hybrid Wallpaper & Theme Detection (`auto`):** Samples the top 10% strip of each display's static wallpaper via `ImageIO` (falling back to macOS `AppleInterfaceStyle`) to pick the right blend mode automatically.
- **WindowServer Keep-Alive:** Includes an imperceptible GPU opacity animation (`0.996` to `1.0`) on the tint layer to prevent WindowServer from auto-flattening the backdrop layer tree after ~1 second of inactivity.
- **Smart Auto-Hide & Multi-Display:** Automatically hides during native fullscreen apps, Mission Control / Exposé, Lock Screen / Screen Savers, and Secure Input password prompts, and adapts when displays are connected or disconnected.
- **Auto-Start on Login:** Registers a `LaunchAgent` so your chosen tint persists across reboots.

> **Tip for Best Results:** Use **Dark Mode** with a pure black menu bar background (e.g., by enabling *Reduce Transparency* in Accessibility → Display, or using a wallpaper with a black top strip). Because Multiply blends against everything behind the menu bar, any non-black background behind the bar will also be tinted.

## Requirements

- macOS (tested on macOS 27 Golden Gate, Apple Silicon)
- Zsh (default shell on macOS)
- Xcode Command Line Tools (`swiftc`), for compiling the native overlay on first run (`xcode-select --install`)

## Installation

```zsh
git clone https://github.com/lost-traveler/macos-menubar-tint.git
cd macos-menubar-tint
chmod +x menubar_tint.zsh
```

## Usage

### Apply a Hex Color

Pass any 6-digit hex color (with or without `#`), or run the script without arguments to be prompted interactively:

```zsh
./menubar_tint.zsh "#FF5500"
```

When only a hex color is provided, `auto` mode is used automatically. You can also pass an optional opacity (`0.05`–`1.0`, default `1.0`) and/or a blend mode (`auto`, `dark`/`multiply`, `light`/`screen`, or `--mode <mode>`):

```zsh
./menubar_tint.zsh "#00E5FF" 0.85
./menubar_tint.zsh "#00E5FF" 0.85 light
./menubar_tint.zsh "#FF5500" --dark
```

Running `./menubar_tint.zsh` with no arguments starts an interactive prompt explaining each mode (`auto`, `dark`, `light`) so you can pick the best fit.

On the first run, `menubar_tint.zsh` compiles `menubar_tint_overlay.swift` into `~/.local/bin/menubar_tint_overlay` (so it persists across reboots) and creates a `LaunchAgent` (`~/Library/LaunchAgents/com.macos.menubar-tint.plist`) to apply your chosen color automatically on login. Subsequent color changes reuse the compiled binary and update immediately.

### Turn Off / Remove the Overlay & Auto-Start & Auto-Start

```zsh
./menubar_tint.zsh off
```

*(Aliases: `stop`, `quit`, `disable`, `0`)* — This stops the overlay immediately and removes the `LaunchAgent` so it will not relaunch on reboot. — This stops the overlay immediately and removes the `LaunchAgent` so it will not relaunch on reboot.

Emergency fallback if you want to terminate the process manually:

```zsh
pkill -f menubar_tint_overlay
```

## License

This project is licensed under the [MIT License](LICENSE), allowing free use, modification, and distribution.

# macos-menubar-tint

<img width="1408" height="881" alt="Captura de pantalla 2026-11-16 a la(s) 10 50 39 am" src="https://github.com/user-attachments/assets/1ce6ab6f-5e19-41d1-abf1-5101849d4cf1" />

A lightweight macOS command-line utility and native Swift overlay that tints the menu bar's white text and icons with any arbitrary hexadecimal color (`#RRGGBB`), without replacing the native macOS menu bar.

## How It Works

macOS does not expose a public setting or API to customize the color of menu bar text and icons directly. This tool solves that by placing a borderless, click-through (`ignoresMouseEvents = true`) `NSWindow` overlay directly over the menu bar on all connected displays:

- **Multiply Blend Mode (`CABackdropLayer` + `CAFilter`):** Uses Core Animation's `multiplyBlendMode` compositing filter so that pure white pixels (`1.0, 1.0, 1.0`) take on your exact target hex color while pure black pixels (`0.0, 0.0, 0.0`) remain untouched.
- **WindowServer Keep-Alive:** Includes an imperceptible GPU opacity animation (`0.996` to `1.0`) on the tint layer to prevent WindowServer from auto-flattening the backdrop layer tree after ~1 second of inactivity.
- **Multi-Display Aware:** Automatically adapts when displays are connected or disconnected.

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

You can also pass an optional opacity/intensity value between `0.05` and `1.0` (defaults to `1.0`):

```zsh
./menubar_tint.zsh "#00E5FF" 0.85
```

On the first run, `menubar_tint.zsh` compiles `menubar_tint_overlay.swift` into `/tmp/menubar_tint_overlay`. Subsequent color changes reuse the compiled binary and update immediately.

### Turn Off / Remove the Overlay

```zsh
./menubar_tint.zsh off
```

*(Aliases: `stop`, `quit`, `disable`, `0`)*

Emergency fallback if you want to terminate the process manually:

```zsh
pkill -f /tmp/menubar_tint_overlay
```

## License

This project is licensed under the [MIT License](LICENSE), allowing free use, modification, and distribution.

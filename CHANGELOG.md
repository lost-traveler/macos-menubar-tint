# Changelog

## [v1.03] - 2026-11-16

### Added
- **Auto-Start on Login (`LaunchAgent`):** Applying a color now automatically creates/updates `~/Library/LaunchAgents/com.macos.menubar-tint.plist` (`RunAtLoad = true`) and registers it via `launchctl bootstrap` so the tint persists across reboots.
- **Persistent Binary Location:** Compiled overlay binary is now stored at `~/.local/bin/menubar_tint_overlay` instead of `/tmp` so it survives system restarts.

### Changed
- Running `./menubar_tint.zsh off` now stops the overlay and cleanly unloads and removes the `LaunchAgent` plist so it will not relaunch on the next login.

## [v1.02] - 2026-11-16

### Fixed
- **Mission Control / Exposé Auto-Hide:** Added lightweight detection for `Dock` full-screen overlay windows (`CGWindowListCopyWindowInfo`) so the menu bar tint automatically hides while Mission Control or Exposé is open and restores immediately upon exiting.

## [v1.01] - 2026-11-16

### Fixed
- **Fullscreen Auto-Hide:** Automatically hides the menu bar tint overlay when an app enters native fullscreen mode (or when the menu bar is hidden) and restores it upon exiting fullscreen.
- **Desktop Click Sampling:** Configured `CABackdropLayer` (`ignoresOffscreenGroups`, `allowsGroupBlending`, `disablesOccludedBackdropBlurs`) and added Space/app activation observers so clicking the desktop no longer turns the menu bar into a solid color block.

## [v1.00] - 2026-11-16

### Added
- Initial release of `menubar_tint.zsh` and `menubar_tint_overlay.swift`.
- Support for tinting macOS menu bar text and icons with any arbitrary 6-digit hex color using `CABackdropLayer` and `multiplyBlendMode`.
- Multi-display support and clean toggle-off (`off` / `stop` / `quit`).

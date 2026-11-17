# Changelog

## [v2.0.0] - 2026-11-17

### Added
- **Light Mode & `screenBlendMode` Support:** Added support for Light Mode and bright menu bar backgrounds using `screenBlendMode`, tinting black text and icons while leaving pure white backgrounds untouched.
- **Hybrid Wallpaper & Appearance Detection (`auto` Mode):** When no mode is specified (or `auto` is selected), the overlay samples the top 10% strip of each display's static wallpaper via `ImageIO` to measure luminance (`< 0.5` selects `multiplyBlendMode`, `>= 0.5` selects `screenBlendMode`), falling back to `AppleInterfaceStyle` and dynamically updating on theme or Space changes.
- **Interactive Mode Prompt & Optional CLI Flags:** Running `./menubar_tint.zsh` without arguments now walks through hex color, opacity, and blend mode selection (`auto`, `dark`, `light`) with explanations of each mode's ideal use case. CLI arguments also accept `auto`/`dark`/`light` (or `--auto`, `--dark`, `--light`, `--mode <mode>`), while passing only a hex code defaults to `auto`.
- **Secure Input Auto-Hide:** Integrated `IsSecureEventInputEnabled()` (`Carbon.HIToolbox`) to automatically hide the overlay while password fields or Secure Keyboard Entry are active, restoring it immediately afterward.
- **DRM Backdrop Fallback:** Enabled `allowsSubstituteColor = true` on `CABackdropLayer` to prevent harsh solid/black artifacts when WindowServer restricts live sampling over DRM-protected content.

## [v1.1.0] - 2026-11-17

### Fixed
- **Mission Control Opening Animation Flash:** Reduced visibility poll interval to `50 ms` and added detection for the top `Dock` Spaces bar so the overlay hides immediately before Mission Control's opening animation begins.
- **Vertical Multi-Display Coordinate Mapping:** `cgRect(for:)` now explicitly uses the primary display (`frame.origin == .zero`) as the coordinate reference when translating AppKit frames to CoreGraphics, preventing fullscreen/overlay mismatches when displays are stacked vertically.
- **Screen Saver & Lock Screen Handling:** Subscribed to `DistributedNotificationCenter` (`com.apple.screenIsLocked`, `com.apple.screenIsUnlocked`, `com.apple.screensaver.didstart`, `com.apple.screensaver.didstop`) plus `ScreenSaverEngine` window checks to hide the overlay while locked or running a screen saver.
- **Wake from Sleep Display Rebuilds:** Listens to `NSWorkspace.didWakeNotification` and rebuilds overlay windows after a `0.6s` delay so displays and `visibleFrame` geometry settle cleanly.
- **iCloud Drive Dataless Source Handling:** `menubar_tint.zsh` now invokes `brctl download` when stored in iCloud Drive to ensure `menubar_tint_overlay.swift` is downloaded locally before compiling.

### Improved
- **Tiling Window Manager & Auto-Hide Menu Bar Mitigation:** Visibility detection now checks for the active `Window Server` `Menubar` strip (`layer == 24`) instead of relying solely on `layer == 0` full-screen window bounds, reducing false hides with tiling window managers and improving behavior when the menu bar auto-hides.

## [v1.03.1] - 2026-11-16

### Changed
- **English Localization:** Translated all CLI prompts, status messages, error outputs, and code comments in `menubar_tint.zsh` and `menubar_tint_overlay.swift` to English.

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

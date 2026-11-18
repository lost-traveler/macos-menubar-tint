# Changelog

## [v1.01] - 2026-11-16

### Fixed
- **Fullscreen Auto-Hide:** Automatically hides the menu bar tint overlay when an app enters native fullscreen mode (or when the menu bar is hidden) and restores it upon exiting fullscreen.
- **Desktop Click Sampling:** Configured `CABackdropLayer` (`ignoresOffscreenGroups`, `allowsGroupBlending`, `disablesOccludedBackdropBlurs`) and added Space/app activation observers so clicking the desktop no longer turns the menu bar into a solid color block.

## [v1.00] - 2026-11-16

### Added
- Initial release of `menubar_tint.zsh` and `menubar_tint_overlay.swift`.
- Support for tinting macOS menu bar text and icons with any arbitrary 6-digit hex color using `CABackdropLayer` and `multiplyBlendMode`.
- Multi-display support and clean toggle-off (`off` / `stop` / `quit`).

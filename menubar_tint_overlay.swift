import AppKit
import Carbon.HIToolbox
import CoreGraphics
import CoreImage
import ImageIO

enum TintMode: String {
    case auto
    case dark
    case light
}

final class OverlayController: NSObject {
    private var windows: [CGDirectDisplayID: NSWindow] = [:]
    private var backdropLayers: [CGDirectDisplayID: CALayer] = [:]
    private var tintLayers: [CGDirectDisplayID: CALayer] = [:]
    private var hiddenState: [CGDirectDisplayID: Bool] = [:]
    private var isScreenLockedOrSaver = false
    private var pollTimer: Timer?
    private var currentPollInterval: TimeInterval = 0.20
    private var burstUntil: Date = .distantPast
    private let idlePollInterval: TimeInterval = 0.20
    private let fastPollInterval: TimeInterval = 0.05
    private let r: CGFloat
    private let g: CGFloat
    private let b: CGFloat
    private let alpha: CGFloat
    private let mode: TintMode

    init(r: CGFloat, g: CGFloat, b: CGFloat, alpha: CGFloat, mode: TintMode) {
        self.r = r
        self.g = g
        self.b = b
        self.alpha = alpha
        self.mode = mode
        super.init()
        rebuildWindows()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        let wsnc = NSWorkspace.shared.notificationCenter
        wsnc.addObserver(
            self,
            selector: #selector(spaceOrAppChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
        wsnc.addObserver(
            self,
            selector: #selector(spaceOrAppChanged),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        wsnc.addObserver(
            self,
            selector: #selector(didWakeFromSleep),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(
            self,
            selector: #selector(screenLockedOrSaverStarted),
            name: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil
        )
        dnc.addObserver(
            self,
            selector: #selector(screenLockedOrSaverStarted),
            name: NSNotification.Name("com.apple.screensaver.didstart"),
            object: nil
        )
        dnc.addObserver(
            self,
            selector: #selector(screenUnlockedOrSaverStopped),
            name: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil
        )
        dnc.addObserver(
            self,
            selector: #selector(screenUnlockedOrSaverStopped),
            name: NSNotification.Name("com.apple.screensaver.didstop"),
            object: nil
        )
        dnc.addObserver(
            self,
            selector: #selector(interfaceThemeChanged),
            name: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )

        schedulePollTimer(interval: idlePollInterval)
    }

    private func schedulePollTimer(interval: TimeInterval) {
        if pollTimer != nil && abs(currentPollInterval - interval) < 0.001 {
            return
        }
        pollTimer?.invalidate()
        currentPollInterval = interval
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.handlePollTick()
        }
        timer.tolerance = interval * 0.2
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func triggerFastPollBurst(duration: TimeInterval = 1.5) {
        let target = Date().addingTimeInterval(duration)
        if target > burstUntil {
            burstUntil = target
        }
        schedulePollTimer(interval: fastPollInterval)
    }

    private func handlePollTick() {
        updateVisibilityForAllScreens(forceRefresh: false)
        if currentPollInterval < idlePollInterval && Date() >= burstUntil {
            schedulePollTimer(interval: idlePollInterval)
        }
    }

    @objc private func screensChanged() {
        rebuildWindows()
    }

    @objc private func didWakeFromSleep() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.rebuildWindows()
        }
    }

    @objc private func screenLockedOrSaverStarted() {
        isScreenLockedOrSaver = true
        updateVisibilityForAllScreens(forceRefresh: false)
    }

    @objc private func screenUnlockedOrSaverStopped() {
        isScreenLockedOrSaver = false
        triggerFastPollBurst()
        updateVisibilityForAllScreens(forceRefresh: true)
    }

    @objc private func interfaceThemeChanged() {
        updateBlendModesForAllScreens()
    }

    @objc private func spaceOrAppChanged() {
        triggerFastPollBurst()
        updateBlendModesForAllScreens()
        updateVisibilityForAllScreens(forceRefresh: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.updateVisibilityForAllScreens(forceRefresh: true)
        }
    }

    private func isSystemDarkMode() -> Bool {
        let match = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
        return match == .darkAqua
    }

    private func topStripLuminance(for screen: NSScreen) -> Double? {
        guard let url = NSWorkspace.shared.desktopImageURL(for: screen) else {
            return nil
        }

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else {
            return nil
        }

        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary) else {
            return nil
        }

        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 64,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else {
            return nil
        }

        let stripHeight = max(1, thumb.height / 10)
        guard let topStrip = thumb.cropping(to: CGRect(x: 0, y: 0, width: thumb.width, height: stripHeight)) else {
            return nil
        }

        var pixel = [UInt8](repeating: 0, count: 4)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                  data: &pixel,
                  width: 1,
                  height: 1,
                  bitsPerComponent: 8,
                  bytesPerRow: 4,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }

        ctx.interpolationQuality = .medium
        ctx.draw(topStrip, in: CGRect(x: 0, y: 0, width: 1, height: 1))

        let pr = Double(pixel[0]) / 255.0
        let pg = Double(pixel[1]) / 255.0
        let pb = Double(pixel[2]) / 255.0
        return 0.2126 * pr + 0.7152 * pg + 0.0722 * pb
    }

    private func resolvedFilterType(for screen: NSScreen) -> (caName: String, ciName: String) {
        let useDarkMultiply: Bool
        switch mode {
        case .dark:
            useDarkMultiply = true
        case .light:
            useDarkMultiply = false
        case .auto:
            if let lum = topStripLuminance(for: screen) {
                useDarkMultiply = lum < 0.5
            } else {
                useDarkMultiply = isSystemDarkMode()
            }
        }

        if useDarkMultiply {
            return ("multiplyBlendMode", "CIMultiplyBlendMode")
        } else {
            return ("screenBlendMode", "CIScreenBlendMode")
        }
    }

    private func makeBlendFilter(for screen: NSScreen) -> Any? {
        let filterNames = resolvedFilterType(for: screen)
        if let caFilterClass = NSClassFromString("CAFilter") as? NSObject.Type {
            let sel = NSSelectorFromString("filterWithType:")
            if caFilterClass.responds(to: sel) {
                return caFilterClass.perform(sel, with: filterNames.caName)?.takeUnretainedValue()
            }
        }
        return CIFilter(name: filterNames.ciName)
    }

    private func updateBlendModesForAllScreens() {
        guard mode == .auto else { return }
        for screen in NSScreen.screens {
            let did = displayID(for: screen)
            guard let tintLayer = tintLayers[did] else { continue }
            tintLayer.compositingFilter = makeBlendFilter(for: screen)
        }
    }

    private func displayID(for screen: NSScreen) -> CGDirectDisplayID {
        return (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    private func cgRect(for screen: NSScreen) -> CGRect {
        let primaryScreen = NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.screens.first
        let mainHeight = primaryScreen?.frame.height ?? screen.frame.height
        let fullFrame = screen.frame
        return CGRect(
            x: fullFrame.minX,
            y: mainHeight - fullFrame.maxY,
            width: fullFrame.width,
            height: fullFrame.height
        )
    }

    private func shouldHideOverlay(for screen: NSScreen, infoList: [[String: Any]]) -> Bool {
        if isScreenLockedOrSaver || IsSecureEventInputEnabled() {
            return true
        }

        let fullFrame = screen.frame
        let visibleFrame = screen.visibleFrame
        let cgScreenRect = cgRect(for: screen)
        let topInset = fullFrame.maxY - visibleFrame.maxY

        var menuBarWindowVisible = false
        var fullscreenAppWindow = false

        for info in infoList {
            guard let layer = info[kCGWindowLayer as String] as? Int,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
                continue
            }

            let owner = info[kCGWindowOwnerName as String] as? String ?? ""
            let winAlpha = info[kCGWindowAlpha as String] as? Double ?? 1.0

            // ScreenSaverEngine fallback
            if owner == "ScreenSaverEngine", bounds.intersects(cgScreenRect) {
                return true
            }

            // Mission Control / Exposé (WindowManager shield at layer 19 on modern macOS; avoid kCGWindowName which is redacted without Screen Recording)
            if owner == "WindowManager",
               layer == 19,
               winAlpha > 0.01,
               bounds.intersects(cgScreenRect),
               bounds.width >= cgScreenRect.width * 0.85,
               bounds.height >= cgScreenRect.height * 0.85 {
                return true
            }

            // Mission Control / Exposé (older macOS Dock layer < 20 or top Spaces bar; ignore auto-hide Dock at layer >= 20)
            if owner == "Dock",
               layer > 0,
               winAlpha > 0.01,
               bounds.intersects(cgScreenRect),
               ((layer < 20 && bounds.width >= cgScreenRect.width * 0.85 && bounds.height >= cgScreenRect.height * 0.85) ||
                (bounds.minY <= cgScreenRect.minY + 5 && bounds.width >= cgScreenRect.width * 0.5 && bounds.height >= 40 && bounds.height <= 250)) {
                return true
            }

            // Active Window Server Menubar strip at the top of this screen (helps with auto-hide & tiling WMs)
            if owner == "Window Server",
               layer == 24,
               bounds.intersects(cgScreenRect),
               bounds.minY >= cgScreenRect.minY - 2,
               bounds.minY <= cgScreenRect.minY + 6,
               bounds.width >= cgScreenRect.width * 0.85,
               bounds.height >= 18,
               bounds.height <= 64 {
                menuBarWindowVisible = true
                if let window = windows[displayID(for: screen)], abs(window.frame.height - bounds.height) > 0.5 {
                    let newRect = NSRect(
                        x: fullFrame.minX,
                        y: fullFrame.maxY - bounds.height,
                        width: fullFrame.width,
                        height: bounds.height
                    )
                    window.setFrame(newRect, display: true)
                }
            }

            // Normal app window covering the entire screen
            if layer == 0,
               abs(bounds.origin.x - cgScreenRect.origin.x) <= 2,
               abs(bounds.origin.y - cgScreenRect.origin.y) <= 2,
               abs(bounds.width - cgScreenRect.width) <= 2,
               abs(bounds.height - cgScreenRect.height) <= 2 {
                fullscreenAppWindow = true
            }
        }

        // If menu bar is visible (either via visibleFrame inset or Window Server Menubar window), keep overlay unless fullscreen hid it
        if topInset < 1.0 && !menuBarWindowVisible {
            return true
        }

        if fullscreenAppWindow && !menuBarWindowVisible {
            return true
        }

        return false
    }

    private func updateVisibilityForAllScreens(forceRefresh: Bool) {
        if isScreenLockedOrSaver {
            for screen in NSScreen.screens {
                let did = displayID(for: screen)
                guard let window = windows[did] else { continue }
                if hiddenState[did] != true || window.isVisible {
                    window.orderOut(nil)
                    hiddenState[did] = true
                }
            }
            return
        }

        let infoList = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []

        for screen in NSScreen.screens {
            let did = displayID(for: screen)
            guard let window = windows[did] else { continue }

            let shouldHide = shouldHideOverlay(for: screen, infoList: infoList)
            let wasHidden = hiddenState[did]

            if shouldHide {
                if wasHidden != true || window.isVisible {
                    window.orderOut(nil)
                    hiddenState[did] = true
                }
            } else {
                if wasHidden != false || !window.isVisible || forceRefresh {
                    window.orderFrontRegardless()
                    if let backdrop = backdropLayers[did] {
                        if backdrop.responds(to: NSSelectorFromString("setEnabled:")) {
                            backdrop.setValue(true, forKey: "enabled")
                        }
                        backdrop.setNeedsDisplay()
                    }
                    hiddenState[did] = false
                }
            }
        }
    }

    private func rebuildWindows() {
        for (_, w) in windows {
            w.orderOut(nil)
        }
        windows.removeAll()
        backdropLayers.removeAll()
        tintLayers.removeAll()
        hiddenState.removeAll()

        guard let backdropClass = NSClassFromString("CABackdropLayer") as? CALayer.Type else {
            fputs("Error: CABackdropLayer is not available on this version of macOS.\n", stderr)
            exit(2)
        }

        let menuBarLevel = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)

        for screen in NSScreen.screens {
            let did = displayID(for: screen)
            let fullFrame = screen.frame
            let visibleFrame = screen.visibleFrame
            let topInset = fullFrame.maxY - visibleFrame.maxY
            let safeTop = screen.safeAreaInsets.top
            let barHeight = topInset > 0 ? topInset : (safeTop > 0 ? safeTop : max(NSStatusBar.system.thickness, 24))

            let barRect = NSRect(
                x: fullFrame.minX,
                y: fullFrame.maxY - barHeight,
                width: fullFrame.width,
                height: barHeight
            )

            let window = NSWindow(
                contentRect: barRect,
                styleMask: .borderless,
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.isOpaque = false
            window.backgroundColor = .clear
            window.ignoresMouseEvents = true
            window.hasShadow = false
            window.level = menuBarLevel
            window.collectionBehavior = [
                .canJoinAllSpaces,
                .stationary,
                .ignoresCycle
            ]

            if window.responds(to: NSSelectorFromString("setShouldAutoFlattenLayerTree:")) {
                window.setValue(false, forKey: "shouldAutoFlattenLayerTree")
            } else if window.responds(to: NSSelectorFromString("_setShouldAutoFlattenLayerTree:")) {
                window.perform(NSSelectorFromString("_setShouldAutoFlattenLayerTree:"), with: NSNumber(value: false))
            }

            let contentView = NSView(frame: NSRect(origin: .zero, size: barRect.size))
            contentView.wantsLayer = true

            let rootLayer = contentView.layer!
            let backdropLayer = backdropClass.init()
            backdropLayer.frame = rootLayer.bounds
            backdropLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            if backdropLayer.responds(to: NSSelectorFromString("setScale:")) {
                backdropLayer.setValue(1.0, forKey: "scale")
            }
            if backdropLayer.responds(to: NSSelectorFromString("setAllowsInPlaceFiltering:")) {
                backdropLayer.setValue(false, forKey: "allowsInPlaceFiltering")
            }
            if backdropLayer.responds(to: NSSelectorFromString("setWindowServerAware:")) {
                backdropLayer.setValue(true, forKey: "windowServerAware")
            }
            if backdropLayer.responds(to: NSSelectorFromString("setIgnoresOffscreenGroups:")) {
                backdropLayer.setValue(true, forKey: "ignoresOffscreenGroups")
            }
            if backdropLayer.responds(to: NSSelectorFromString("setAllowsGroupBlending:")) {
                backdropLayer.setValue(true, forKey: "allowsGroupBlending")
            }
            if backdropLayer.responds(to: NSSelectorFromString("setDisablesOccludedBackdropBlurs:")) {
                backdropLayer.setValue(false, forKey: "disablesOccludedBackdropBlurs")
            }
            if backdropLayer.responds(to: NSSelectorFromString("setAllowsSubstituteColor:")) {
                backdropLayer.setValue(false, forKey: "allowsSubstituteColor")
            }

            let tintLayer = CALayer()
            tintLayer.frame = rootLayer.bounds
            tintLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            tintLayer.backgroundColor = CGColor(srgbRed: r, green: g, blue: b, alpha: alpha)
            tintLayer.compositingFilter = makeBlendFilter(for: screen)

            // Discrete pulse every 0.8s (instead of 60/120Hz interpolation) to prevent WindowServer flattening while minimizing CPU/energy
            let keepAlive = CAKeyframeAnimation(keyPath: "opacity")
            keepAlive.values = [0.996, 1.0]
            keepAlive.keyTimes = [0.0, 0.5]
            keepAlive.duration = 1.6
            keepAlive.calculationMode = .discrete
            keepAlive.repeatCount = .infinity
            keepAlive.isRemovedOnCompletion = false
            tintLayer.add(keepAlive, forKey: "keepAlive")

            rootLayer.addSublayer(backdropLayer)
            rootLayer.addSublayer(tintLayer)

            window.contentView = contentView
            windows[did] = window
            backdropLayers[did] = backdropLayer
            tintLayers[did] = tintLayer
        }

        updateVisibilityForAllScreens(forceRefresh: true)
    }
}

guard CommandLine.arguments.count >= 4,
      let r = Double(CommandLine.arguments[1]),
      let g = Double(CommandLine.arguments[2]),
      let b = Double(CommandLine.arguments[3]) else {
    fputs("Usage: menubar_tint_overlay <r> <g> <b> [alpha] [auto|dark|light]\n", stderr)
    exit(1)
}

let alpha = CommandLine.arguments.count >= 5 ? (Double(CommandLine.arguments[4]) ?? 1.0) : 1.0
let modeArg = CommandLine.arguments.count >= 6 ? CommandLine.arguments[5].lowercased() : "auto"
let mode: TintMode
switch modeArg {
case "dark", "multiply":
    mode = .dark
case "light", "screen":
    mode = .light
default:
    mode = .auto
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let controller = OverlayController(r: r, g: g, b: b, alpha: alpha, mode: mode)
_ = controller
app.run()

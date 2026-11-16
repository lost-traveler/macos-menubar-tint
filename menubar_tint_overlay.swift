import AppKit
import CoreGraphics
import CoreImage

final class OverlayController: NSObject {
    private var windows: [CGDirectDisplayID: NSWindow] = [:]
    private var backdropLayers: [CGDirectDisplayID: CALayer] = [:]
    private var hiddenState: [CGDirectDisplayID: Bool] = [:]
    private var pollTimer: Timer?
    private let r: CGFloat
    private let g: CGFloat
    private let b: CGFloat
    private let alpha: CGFloat

    init(r: CGFloat, g: CGFloat, b: CGFloat, alpha: CGFloat) {
        self.r = r
        self.g = g
        self.b = b
        self.alpha = alpha
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

        // Detecta Mission Control / Exposé sin esperar notificaciones de cambio de Space
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.updateVisibilityForAllScreens(forceRefresh: false)
        }
    }

    @objc private func screensChanged() {
        rebuildWindows()
    }

    @objc private func spaceOrAppChanged() {
        updateVisibilityForAllScreens(forceRefresh: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.updateVisibilityForAllScreens(forceRefresh: true)
        }
    }

    private func makeMultiplyFilter() -> Any? {
        if let caFilterClass = NSClassFromString("CAFilter") as? NSObject.Type {
            let sel = NSSelectorFromString("filterWithType:")
            if caFilterClass.responds(to: sel) {
                return caFilterClass.perform(sel, with: "multiplyBlendMode")?.takeUnretainedValue()
            }
        }
        return CIFilter(name: "CIMultiplyBlendMode")
    }

    private func displayID(for screen: NSScreen) -> CGDirectDisplayID {
        return (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    private func shouldHideOverlay(for screen: NSScreen) -> Bool {
        let fullFrame = screen.frame
        let visibleFrame = screen.visibleFrame

        // 1. Barra de menús oculta (pantalla completa o auto-ocultar)
        if (fullFrame.maxY - visibleFrame.maxY) < 1.0 {
            return true
        }

        // Convierte coordenadas de AppKit (abajo-izquierda) a CoreGraphics (arriba-izquierda)
        guard let mainScreen = NSScreen.screens.first else { return false }
        let mainHeight = mainScreen.frame.height
        let cgScreenRect = CGRect(
            x: fullFrame.minX,
            y: mainHeight - fullFrame.maxY,
            width: fullFrame.width,
            height: fullFrame.height
        )

        guard let infoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }

        for info in infoList {
            guard let layer = info[kCGWindowLayer as String] as? Int,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
                continue
            }

            // 2. Ventana de app en pantalla completa (nivel normal cubriendo toda la pantalla)
            if layer == 0,
               abs(bounds.origin.x - cgScreenRect.origin.x) <= 2,
               abs(bounds.origin.y - cgScreenRect.origin.y) <= 2,
               abs(bounds.width - cgScreenRect.width) <= 2,
               abs(bounds.height - cgScreenRect.height) <= 2 {
                return true
            }

            // 3. Mission Control / Exposé (Dock dibuja una ventana superpuesta de pantalla completa con layer > 0)
            if let owner = info[kCGWindowOwnerName as String] as? String,
               owner == "Dock",
               layer > 0,
               bounds.intersects(cgScreenRect),
               bounds.width >= cgScreenRect.width * 0.85,
               bounds.height >= cgScreenRect.height * 0.85 {
                return true
            }
        }

        return false
    }

    private func updateVisibilityForAllScreens(forceRefresh: Bool) {
        for screen in NSScreen.screens {
            let did = displayID(for: screen)
            guard let window = windows[did] else { continue }

            let shouldHide = shouldHideOverlay(for: screen)
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
        hiddenState.removeAll()

        guard let backdropClass = NSClassFromString("CABackdropLayer") as? CALayer.Type else {
            fputs("Error: CABackdropLayer no está disponible en esta versión de macOS.\n", stderr)
            exit(2)
        }

        let menuBarLevel = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)

        for screen in NSScreen.screens {
            let did = displayID(for: screen)
            let fullFrame = screen.frame
            let visibleFrame = screen.visibleFrame
            let topInset = fullFrame.maxY - visibleFrame.maxY
            let barHeight = topInset > 0 ? topInset : max(NSStatusBar.system.thickness, 24)

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

            let tintLayer = CALayer()
            tintLayer.frame = rootLayer.bounds
            tintLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            tintLayer.backgroundColor = CGColor(srgbRed: r, green: g, blue: b, alpha: alpha)
            tintLayer.compositingFilter = makeMultiplyFilter()

            // Mantiene el árbol de capas activo en GPU para impedir el aplanado tras 1s de inactividad
            let keepAlive = CABasicAnimation(keyPath: "opacity")
            keepAlive.fromValue = 0.996
            keepAlive.toValue = 1.0
            keepAlive.duration = 0.45
            keepAlive.autoreverses = true
            keepAlive.repeatCount = .infinity
            keepAlive.isRemovedOnCompletion = false
            tintLayer.add(keepAlive, forKey: "keepAlive")

            rootLayer.addSublayer(backdropLayer)
            rootLayer.addSublayer(tintLayer)

            window.contentView = contentView
            windows[did] = window
            backdropLayers[did] = backdropLayer
        }

        updateVisibilityForAllScreens(forceRefresh: true)
    }
}

guard CommandLine.arguments.count >= 4,
      let r = Double(CommandLine.arguments[1]),
      let g = Double(CommandLine.arguments[2]),
      let b = Double(CommandLine.arguments[3]) else {
    fputs("Uso: menubar_tint_overlay <r> <g> <b> [alpha]\n", stderr)
    exit(1)
}

let alpha = CommandLine.arguments.count >= 5 ? (Double(CommandLine.arguments[4]) ?? 1.0) : 1.0

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let controller = OverlayController(r: r, g: g, b: b, alpha: alpha)
_ = controller
app.run()

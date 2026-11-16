import AppKit
import CoreImage

final class OverlayController: NSObject {
    private var windows: [NSWindow] = []
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
    }

    @objc private func screensChanged() {
        rebuildWindows()
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

    private func rebuildWindows() {
        for w in windows {
            w.orderOut(nil)
        }
        windows.removeAll()

        guard let backdropClass = NSClassFromString("CABackdropLayer") as? CALayer.Type else {
            fputs("Error: CABackdropLayer no está disponible en esta versión de macOS.\n", stderr)
            exit(2)
        }

        let menuBarLevel = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)

        for screen in NSScreen.screens {
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
                .ignoresCycle,
                .fullScreenAuxiliary
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
            window.orderFrontRegardless()
            windows.append(window)
        }
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

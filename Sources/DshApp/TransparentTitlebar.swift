import AppKit
import SwiftUI

@MainActor
enum TitlebarChrome {
    private static let clearMask = NSImage(size: NSSize(width: 1, height: 1), flipped: false) { rect in
        NSColor.clear.setFill()
        rect.fill()
        return true
    }

    private static weak var window: NSWindow?
    private static weak var fillView: SidebarFillView?

    static func attach(to window: NSWindow?) {
        guard let window else { return }
        self.window = window
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.styleMask.insert(.fullSizeContentView)
        window.backgroundColor = .windowBackgroundColor
        stripMaterials(in: window)
    }

    static func update(width: CGFloat, sidebar: NSColor) {
        guard width > 0 else {
            clear()
            return
        }
        if let window {
            stripMaterials(in: window)
            installFill(in: window)
        }
        fillView?.sidebarColor = sidebar
        fillView?.sidebarWidth = width
    }

    static func clear() {
        fillView?.sidebarWidth = 0
        fillView?.sidebarColor = .clear
    }

    private static func installFill(in window: NSWindow) {
        guard let close = window.standardWindowButton(.closeButton),
              let titlebar = close.superview else { return }

        let fill: SidebarFillView
        if let existing = fillView, existing.superview === titlebar {
            fill = existing
        } else {
            fillView?.removeFromSuperview()
            fill = SidebarFillView(frame: titlebar.bounds)
            fillView = fill
        }

        fill.frame = titlebar.bounds
        fill.autoresizingMask = [.width, .height]
        fill.wantsLayer = true
        fill.layer?.zPosition = 50
        if fill.superview !== titlebar {
            titlebar.addSubview(fill, positioned: .below, relativeTo: close)
        }
        for button in [close, window.standardWindowButton(.miniaturizeButton), window.standardWindowButton(.zoomButton)].compactMap({ $0 }) {
            button.wantsLayer = true
            button.layer?.zPosition = 200
        }
    }

    private static func stripMaterials(in window: NSWindow) {
        guard let close = window.standardWindowButton(.closeButton) else { return }
        var node: NSView? = close.superview
        var seen = Set<ObjectIdentifier>()
        while let view = node, seen.insert(ObjectIdentifier(view)).inserted {
            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor.clear.cgColor
            neutralize(view)
            for subview in view.subviews where !(subview is NSButton) {
                neutralize(subview)
            }
            if view === window.contentView { break }
            node = view.superview
        }
    }

    private static func neutralize(_ view: NSView) {
        if let effect = view as? NSVisualEffectView {
            effect.material = .underWindowBackground
            effect.blendingMode = .behindWindow
            effect.state = .inactive
            effect.isEmphasized = false
            effect.maskImage = clearMask
            effect.wantsLayer = true
            effect.layer?.backgroundColor = NSColor.clear.cgColor
        }
        let name = NSStringFromClass(type(of: view))
        if name.contains("Decoration") || name.contains("Background") {
            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor.clear.cgColor
        }
    }
}

final class SidebarFillView: NSView {
    private let fillLayer = CALayer()

    var sidebarWidth: CGFloat = 0 {
        didSet { layoutFill() }
    }

    var sidebarColor: NSColor = .clear {
        didSet { fillLayer.backgroundColor = sidebarColor.cgColor }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        fillLayer.anchorPoint = .zero
        layer?.addSublayer(fillLayer)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        layoutFill()
    }

    private func layoutFill() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fillLayer.backgroundColor = sidebarColor.cgColor
        fillLayer.frame = CGRect(x: 0, y: 0, width: min(sidebarWidth, bounds.width), height: bounds.height)
        CATransaction.commit()
    }
}

struct TitlebarChromeHost: NSViewRepresentable {
    func makeNSView(context: Context) -> HostView {
        HostView()
    }

    func updateNSView(_ nsView: HostView, context: Context) {
        nsView.apply()
    }

    final class HostView: NSView {
        override var intrinsicContentSize: NSSize { .zero }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
            DispatchQueue.main.async { [weak self] in
                self?.apply()
            }
        }

        func apply() {
            TitlebarChrome.attach(to: window)
        }
    }
}

import AppKit
import SwiftUI

struct LaunchSplash: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var revealed = false

    var body: some View {
        ZStack {
            groundProjection
            whale
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppCanvas.fill(colorScheme))
        .ignoresSafeArea()
        .onAppear {
            if reduceMotion {
                revealed = true
                return
            }
            withAnimation(.timingCurve(0.16, 1, 0.3, 1, duration: 1.05)) {
                revealed = true
            }
        }
    }

    private var whale: some View {
        WhaleGlyph(size: 128, colorScheme: colorScheme)
            .opacity(revealed ? 1 : 0)
            .scaleEffect(revealed ? 1 : 0.88)
            .offset(y: revealed ? 0 : 20)
    }

    private var groundProjection: some View {
        ZStack {
            flattenedWhale
                .blur(radius: 14)
                .opacity(colorScheme == .dark ? 0.55 : 0.28)
                .scaleEffect(x: 1.18, y: 1, anchor: .bottom)
            flattenedWhale
                .blur(radius: 4)
                .opacity(colorScheme == .dark ? 0.95 : 0.55)
        }
        .opacity(revealed ? 1 : 0)
    }

    private var flattenedWhale: some View {
        WhaleGlyph(size: 128, colorScheme: colorScheme, ink: .black)
            .rotation3DEffect(
                .degrees(80),
                axis: (x: 1, y: 0, z: 0),
                anchor: .bottom,
                perspective: 0.55
            )
            .scaleEffect(x: 1.22, y: 1, anchor: .bottom)
            .offset(y: 10)
    }
}

enum AppCanvas {
    static func fill(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 21 / 255, green: 21 / 255, blue: 23 / 255)
            : Color.white
    }

    static var windowColor: NSColor {
        NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return dark
                ? NSColor(srgbRed: 21 / 255, green: 21 / 255, blue: 23 / 255, alpha: 1)
                : .white
        }
    }
}

struct WhaleGlyph: View {
    var size: CGFloat
    var colorScheme: ColorScheme
    var ink: Color? = nil

    var body: some View {
        Group {
            if let image = WhaleImage.template {
                Image(nsImage: image)
                    .resizable()
                    .renderingMode(.template)
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            }
        }
        .frame(width: size, height: size)
        .foregroundStyle(ink ?? (colorScheme == .dark ? .white : Color(red: 15 / 255, green: 17 / 255, blue: 21 / 255)))
        .compositingGroup()
    }
}

@MainActor
enum WhaleImage {
    static let template: NSImage? = {
        guard let url = Bundle.module.url(forResource: "whale", withExtension: "svg") else {
            return nil
        }
        let image = NSImage(contentsOf: url)
        image?.isTemplate = true
        image?.size = NSSize(width: 512, height: 512)
        return image
    }()
}

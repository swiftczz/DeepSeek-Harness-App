import AppKit
import SwiftUI

enum LaunchMotion {
    static let duration: Duration = .milliseconds(1740)
    static let whaleSize: CGFloat = 132
}

struct LaunchSplash: View {
    @Binding var settled: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var bouncePlay = false

    var body: some View {
        ZStack {
            canvas
            mark
        }
        .ignoresSafeArea()
        .task {
            if reduceMotion {
                settled = true
                return
            }
            bouncePlay = true
            try? await Task.sleep(for: LaunchMotion.duration)
            guard !Task.isCancelled else { return }
            settled = true
        }
    }

    @ViewBuilder
    private var mark: some View {
        let scheme = colorScheme
        if reduceMotion {
            BounceMark(frame: BounceFrame(), colorScheme: scheme)
        } else {
            Color.clear
                .frame(width: LaunchMotion.whaleSize + 80, height: LaunchMotion.whaleSize + 70)
                .keyframeAnimator(initialValue: BounceFrame(), trigger: bouncePlay) { _, frame in
                    BounceMark(frame: frame, colorScheme: scheme)
                } keyframes: { _ in
                    KeyframeTrack(\.y) {
                        LinearKeyframe(8, duration: 0.12)
                        SpringKeyframe(-30, duration: 0.34)
                        SpringKeyframe(0, duration: 0.26)
                        LinearKeyframe(0, duration: 0.18)
                        LinearKeyframe(6, duration: 0.10)
                        SpringKeyframe(-22, duration: 0.30)
                        SpringKeyframe(0, duration: 0.24)
                        LinearKeyframe(0, duration: 0.20)
                    }
                    KeyframeTrack(\.sx) {
                        LinearKeyframe(1.14, duration: 0.12)
                        LinearKeyframe(0.90, duration: 0.34)
                        LinearKeyframe(1.16, duration: 0.10)
                        SpringKeyframe(1.00, duration: 0.34)
                        LinearKeyframe(1.10, duration: 0.10)
                        LinearKeyframe(0.93, duration: 0.30)
                        LinearKeyframe(1.10, duration: 0.10)
                        SpringKeyframe(1.00, duration: 0.34)
                    }
                    KeyframeTrack(\.sy) {
                        LinearKeyframe(0.86, duration: 0.12)
                        LinearKeyframe(1.14, duration: 0.34)
                        LinearKeyframe(0.86, duration: 0.10)
                        SpringKeyframe(1.00, duration: 0.34)
                        LinearKeyframe(0.90, duration: 0.10)
                        LinearKeyframe(1.10, duration: 0.30)
                        LinearKeyframe(0.90, duration: 0.10)
                        SpringKeyframe(1.00, duration: 0.34)
                    }
                    KeyframeTrack(\.shadowSX) {
                        LinearKeyframe(0.82, duration: 0.12)
                        LinearKeyframe(1.55, duration: 0.34)
                        LinearKeyframe(0.72, duration: 0.10)
                        SpringKeyframe(1.00, duration: 0.34)
                        LinearKeyframe(0.88, duration: 0.10)
                        LinearKeyframe(1.35, duration: 0.30)
                        LinearKeyframe(0.80, duration: 0.10)
                        SpringKeyframe(1.00, duration: 0.34)
                    }
                    KeyframeTrack(\.shadowOpacity) {
                        LinearKeyframe(0.40, duration: 0.12)
                        LinearKeyframe(0.10, duration: 0.34)
                        LinearKeyframe(0.46, duration: 0.10)
                        SpringKeyframe(0.24, duration: 0.34)
                        LinearKeyframe(0.34, duration: 0.10)
                        LinearKeyframe(0.12, duration: 0.30)
                        LinearKeyframe(0.38, duration: 0.10)
                        SpringKeyframe(0.24, duration: 0.34)
                    }
                    KeyframeTrack(\.shadowBlur) {
                        LinearKeyframe(3, duration: 0.12)
                        LinearKeyframe(10, duration: 0.34)
                        LinearKeyframe(2, duration: 0.10)
                        SpringKeyframe(5, duration: 0.34)
                        LinearKeyframe(3.5, duration: 0.10)
                        LinearKeyframe(8, duration: 0.30)
                        LinearKeyframe(2.5, duration: 0.10)
                        SpringKeyframe(5, duration: 0.34)
                    }
                }
        }
    }

    private var canvas: some View {
        (colorScheme == .dark
            ? Color(red: 21 / 255, green: 21 / 255, blue: 23 / 255)
            : Color.white)
    }
}

private struct BounceMark: View {
    var frame: BounceFrame
    var colorScheme: ColorScheme

    var body: some View {
        ZStack(alignment: .bottom) {
            Ellipse()
                .fill(shadowColor)
                .frame(width: LaunchMotion.whaleSize * 0.75, height: 18)
                .blur(radius: frame.shadowBlur)
                .scaleEffect(x: frame.shadowSX, y: 1)
                .opacity(frame.shadowOpacity)
                .offset(y: 12)

            whale
                .frame(width: LaunchMotion.whaleSize, height: LaunchMotion.whaleSize)
                .foregroundStyle(markColor)
                .scaleEffect(x: frame.sx, y: frame.sy, anchor: .bottom)
                .offset(y: frame.y)
        }
        .frame(
            width: LaunchMotion.whaleSize + 80,
            height: LaunchMotion.whaleSize + 70,
            alignment: .bottom
        )
    }

    private var markColor: Color {
        colorScheme == .dark ? .white : Color(red: 15 / 255, green: 17 / 255, blue: 21 / 255)
    }

    private var shadowColor: Color {
        colorScheme == .dark ? Color.black : Color(red: 15 / 255, green: 17 / 255, blue: 21 / 255)
    }

    @ViewBuilder
    private var whale: some View {
        if let image = WhaleImage.template {
            Image(nsImage: image)
                .resizable()
                .renderingMode(.template)
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        }
    }
}

private struct BounceFrame {
    var y: CGFloat = 0
    var sx: CGFloat = 1
    var sy: CGFloat = 1
    var shadowSX: CGFloat = 1
    var shadowOpacity: CGFloat = 0.24
    var shadowBlur: CGFloat = 5
}

@MainActor
private enum WhaleImage {
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

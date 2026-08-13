import SwiftUI

struct StatusScreen: View {
    var message: String?
    var isError = false
    var onRetry: (() -> Void)?

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "sparkle")
                .font(.system(size: 42, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isError ? Color.red : Color.accentColor)

            Text("DeepSeek Harness")
                .font(.system(size: 25, weight: .semibold))
                .tracking(-0.4)

            if let message, !message.isEmpty {
                Text(message)
                    .font(.system(size: 14))
                    .foregroundStyle(isError ? Color.red.opacity(0.9) : Color.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
                    .textSelection(.enabled)
            }

            if isError {
                Button("重试") {
                    onRetry?()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}

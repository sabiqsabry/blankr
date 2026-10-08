import SwiftUI

/// Buttons give a small, springy press: they dip and soften while held, then bounce back
/// on release. Respects Reduce Motion (keeps the fade, drops the movement).
struct PressableButtonStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.84

    func makeBody(configuration: Configuration) -> some View {
        PressableBody(configuration: configuration, pressedScale: pressedScale)
    }

    private struct PressableBody: View {
        let configuration: Configuration
        let pressedScale: CGFloat
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(configuration.isPressed ? 0.09 : 0))
                )
                .scaleEffect(configuration.isPressed && !reduceMotion ? pressedScale : 1)
                .opacity(configuration.isPressed ? 0.8 : 1)
                .animation(
                    configuration.isPressed
                        ? .easeOut(duration: 0.08)
                        : .spring(response: 0.32, dampingFraction: 0.5),
                    value: configuration.isPressed
                )
                .contentShape(Rectangle())
        }
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
}

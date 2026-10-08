import SwiftUI
import AppKit

/// Single-click selects tab; double-click starts rename.
struct TabTitleLabel: NSViewRepresentable {
    let title: String
    var toolTip: String? = nil
    let isSelected: Bool
    var fontSize: CGFloat = 12
    let onSelect: () -> Void
    let onRename: () -> Void

    func makeNSView(context: Context) -> TitleHitView {
        let view = TitleHitView()
        let label = NSTextField(labelWithString: title)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        view.toolTip = toolTip
        context.coordinator.label = label
        context.coordinator.applyStyle(isSelected: isSelected, fontSize: fontSize)
        context.coordinator.onSelect = onSelect
        context.coordinator.onRename = onRename

        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: TitleHitView, context: Context) {
        nsView.toolTip = toolTip
        context.coordinator.label?.stringValue = title
        context.coordinator.applyStyle(isSelected: isSelected, fontSize: fontSize)
        context.coordinator.onSelect = onSelect
        context.coordinator.onRename = onRename
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class TitleHitView: NSView {
        weak var coordinator: Coordinator?
        private var singleClickWorkItem: DispatchWorkItem?

        deinit {
            singleClickWorkItem?.cancel()
        }

        override func mouseDown(with event: NSEvent) {
            guard let c = coordinator else {
                super.mouseDown(with: event)
                return
            }
            if event.clickCount >= 2 {
                singleClickWorkItem?.cancel()
                singleClickWorkItem = nil
                c.onRename?()
                return
            }
            singleClickWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.coordinator?.onSelect?()
                self?.singleClickWorkItem = nil
            }
            singleClickWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: work)
        }
    }

    final class Coordinator: NSObject {
        weak var label: NSTextField?

        var onSelect: (() -> Void)?
        var onRename: (() -> Void)?

        func applyStyle(isSelected: Bool, fontSize: CGFloat) {
            label?.font = NSFont.systemFont(ofSize: fontSize, weight: isSelected ? .semibold : .regular)
            label?.textColor = isSelected ? .labelColor : .secondaryLabelColor
        }
    }
}

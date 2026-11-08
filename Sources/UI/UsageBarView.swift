import Cocoa

/// The original OpencodeDashboard status-bar look: up to three colored
/// usage bars with the reset countdown beside each one.
final class UsageBarView: NSView {
    var onOpenMenu: (() -> Void)?

    private var items: [UsageItem] = []
    private var state: DisplayState = .setup

    enum DisplayState {
        case normal
        case loading
        case error
        case setup
    }

    private let barColors: [NSColor] = [.systemGreen, .systemBlue, .systemOrange]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("OpenCode usage")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(with newItems: [UsageItem], state newState: DisplayState) {
        items = newItems
        state = newState
        setAccessibilityValue(description())
        needsDisplay = true
    }

    private var stateColor: NSColor? {
        switch state {
        case .normal: return nil
        case .loading: return .systemGray
        case .error: return .systemOrange
        case .setup: return .systemGray
        }
    }

    private func description() -> String {
        switch state {
        case .setup: return "Setup needed"
        case .loading: return "Loading"
        case .error: return "Error updating usage"
        case .normal:
            return items.map { "\($0.label) \($0.percent)%" }.joined(separator: ", ")
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.set()
        bounds.fill()

        let barCount = min(items.count, 3)
        let forcedColor = stateColor
        if state == .setup {
            drawEmptyBars()
            return
        }
        guard barCount > 0 else {
            // Loading or error with no previous data: draw three faint bars.
            drawEmptyBars()
            return
        }

        let barHeight: CGFloat = 4
        let gap: CGFloat = 3
        let topPad: CGFloat = 2
        let leftPad: CGFloat = 4
        let barWidth: CGFloat = 60
        let textX = leftPad + barWidth + 4

        for i in 0..<barCount {
            let item = items[i]
            let baseColor = i < barColors.count ? barColors[i] : .systemGray
            let color = forcedColor ?? baseColor
            let y = topPad + CGFloat(i) * (barHeight + gap)

            color.withAlphaComponent(0.2).set()
            NSBezierPath(roundedRect: NSRect(x: leftPad, y: y, width: barWidth, height: barHeight), xRadius: 1.5, yRadius: 1.5).fill()

            let fillWidth = max(2, barWidth * CGFloat(item.percent) / 100)
            color.set()
            NSBezierPath(roundedRect: NSRect(x: leftPad, y: y, width: fillWidth, height: barHeight), xRadius: 1.5, yRadius: 1.5).fill()

            if !item.resetShort.isEmpty, state != .error {
                let text = item.resetShort as NSString
                let textFont = NSFont.monospacedDigitSystemFont(ofSize: 7, weight: .regular)
                let textSize = text.size(withAttributes: [.font: textFont])
                let rowCenter = y + barHeight / 2
                let textPoint = NSPoint(x: textX, y: rowCenter - textSize.height / 2)
                text.draw(at: textPoint, withAttributes: [
                    .font: textFont,
                    .foregroundColor: NSColor.labelColor,
                ])
            }
        }
    }

    private func drawEmptyBars() {
        let barHeight: CGFloat = 4
        let gap: CGFloat = 3
        let topPad: CGFloat = 2
        let leftPad: CGFloat = 4
        let barWidth: CGFloat = 60
        let color = stateColor ?? .systemGray
        for i in 0..<3 {
            let y = topPad + CGFloat(i) * (barHeight + gap)
            color.withAlphaComponent(0.2).set()
            NSBezierPath(roundedRect: NSRect(x: leftPad, y: y, width: barWidth, height: barHeight), xRadius: 1.5, yRadius: 1.5).fill()
            // Low fill hints at "waiting for data"
            color.set()
            NSBezierPath(roundedRect: NSRect(x: leftPad, y: y, width: barWidth * 0.2, height: barHeight), xRadius: 1.5, yRadius: 1.5).fill()
        }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: preferredWidth, height: 22)
    }

    /// Width the controller should size the status item to; mirrors the
    /// draw() layout: leftPad(4) + bars(60) + gap(4) + widest reset text + pad.
    var preferredWidth: CGFloat { 68 }

    override func mouseDown(with event: NSEvent) {
        onOpenMenu?()
    }

    override func rightMouseDown(with event: NSEvent) {
        onOpenMenu?()
    }
}

// A one-line label that slides sideways when its text is wider than the label, like a song title on
// a car radio: after a pause the text moves left until its end has passed, with the start following
// again behind a gap, and this repeats. Text that fits stands still. The edges fade while it slides.
// The movement is one Core Animation animation, so no timer runs.

import AppKit

let marqueeSpeed: CGFloat = 30  // points per second
let marqueePauseSeconds: CFTimeInterval = 1.5
let marqueeGap: CGFloat = 40
let marqueeFadeWidth: CGFloat = 10

final class MarqueeField: NSView {
    private let strip = NSView()
    private let copies = [NSTextField(labelWithString: ""), NSTextField(labelWithString: "")]
    private let fadeMask = CAGradientLayer()
    private var text = ""

    init(font: NSFont, color: NSColor) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        strip.wantsLayer = true
        addSubview(strip)
        for copy in copies {
            copy.font = font
            copy.textColor = color
            copy.lineBreakMode = .byClipping
            strip.addSubview(copy)
        }
        fadeMask.startPoint = CGPoint(x: 0, y: 0.5)
        fadeMask.endPoint = CGPoint(x: 1, y: 0.5)
        fadeMask.colors = [NSColor.clear, .black, .black, .clear].map(\.cgColor)
    }

    required init?(coder: NSCoder) { nil }

    var stringValue: String {
        get { text }
        set {
            guard newValue != text else { return }
            text = newValue
            copies.forEach { $0.stringValue = newValue }
            restart()
        }
    }

    /// Whether the text is moving (it is wider than the label).
    var isSliding: Bool { strip.layer?.animation(forKey: "marquee") != nil }

    // Clicks go through to the card behind, so the title can be used to drag the card too.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func setFrameSize(_ newSize: NSSize) {
        let changed = newSize != frame.size
        super.setFrameSize(newSize)
        if changed { restart() }
    }

    private func restart() {
        let textWidth = ceil(copies[0].intrinsicContentSize.width)
        let height = bounds.height
        let slides = bounds.width > 0 && textWidth > bounds.width
        strip.layer?.removeAnimation(forKey: "marquee")
        copies[0].frame = NSRect(x: 0, y: 0, width: max(textWidth, bounds.width), height: height)
        copies[1].frame = NSRect(x: textWidth + marqueeGap, y: 0, width: textWidth, height: height)
        copies[1].isHidden = !slides
        strip.frame = NSRect(x: 0, y: 0, width: slides ? textWidth * 2 + marqueeGap : bounds.width, height: height)
        layer?.mask = slides ? fadeMask : nil
        guard slides else { return }
        fadeMask.frame = bounds
        let edge = NSNumber(value: Double(marqueeFadeWidth / bounds.width))
        fadeMask.locations = [0, edge, NSNumber(value: 1 - edge.doubleValue), 1]
        // Wait, slide by one text and gap (the second copy then sits where the first began), repeat.
        let distance = textWidth + marqueeGap
        let travel = CFTimeInterval(distance / marqueeSpeed)
        let slide = CAKeyframeAnimation(keyPath: "transform.translation.x")
        slide.values = [0, 0, -distance]
        slide.keyTimes = [0, NSNumber(value: marqueePauseSeconds / (marqueePauseSeconds + travel)), 1]
        slide.duration = marqueePauseSeconds + travel
        slide.repeatCount = .infinity
        strip.layer?.add(slide, forKey: "marquee")
    }
}

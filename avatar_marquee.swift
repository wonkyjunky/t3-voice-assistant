// A one-line label that slides sideways when its text is wider than the label, like a song title on
// a car radio: after a pause the text moves left until its end has passed, with the start following
// again behind a gap, and this repeats. Text that fits stands still. The edges fade while it slides.
// The movement is one Core Animation animation, so no timer runs.
//
// The text is drawn by text layers, whole: AppKit text fields draw only the part of themselves that
// is in view, so a sliding field showed its first words and then blank space.

import AppKit

let marqueeSpeed: CGFloat = 30  // points per second
let marqueePauseSeconds: CFTimeInterval = 1.5
let marqueeGap: CGFloat = 40
let marqueeFadeWidth: CGFloat = 10

final class MarqueeField: NSView {
    private let strip = CALayer()
    private let copies = [CATextLayer(), CATextLayer()]
    private let fadeMask = CAGradientLayer()
    private let font: NSFont
    private let color: NSColor
    private var text = ""

    init(font: NSFont, color: NSColor) {
        self.font = font
        self.color = color
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.addSublayer(strip)
        for copy in copies {
            copy.isWrapped = false
            copy.truncationMode = .none
            copy.alignmentMode = .left
            strip.addSublayer(copy)
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
            restart()
        }
    }

    /// Whether the text is moving (it is wider than the label).
    var isSliding: Bool { strip.animation(forKey: "marquee") != nil }

    // Clicks go through to the card behind, so the title can be used to drag the card too.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func setFrameSize(_ newSize: NSSize) {
        let changed = newSize != frame.size
        super.setFrameSize(newSize)
        if changed { restart() }
    }

    // Sharp text on a Retina screen, and again when the window moves to another screen.
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2
        copies.forEach { $0.contentsScale = scale }
    }

    private func restart() {
        let words = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        let size = words.size()
        let textWidth = ceil(size.width)
        let textHeight = ceil(size.height)
        let slides = bounds.width > 0 && textWidth > bounds.width
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        strip.removeAnimation(forKey: "marquee")
        let y = (bounds.height - textHeight) / 2
        for (index, copy) in copies.enumerated() {
            copy.string = words
            copy.contentsScale = window?.backingScaleFactor ?? 2
            copy.frame = CGRect(x: CGFloat(index) * (textWidth + marqueeGap), y: y, width: textWidth, height: textHeight)
        }
        copies[1].isHidden = !slides
        strip.frame = CGRect(x: 0, y: 0, width: slides ? textWidth * 2 + marqueeGap : bounds.width, height: bounds.height)
        layer?.mask = slides ? fadeMask : nil
        if slides {
            fadeMask.frame = bounds
            let edge = Double(marqueeFadeWidth / bounds.width)
            fadeMask.locations = [0, NSNumber(value: edge), NSNumber(value: 1 - edge), 1]
        }
        CATransaction.commit()
        guard slides else { return }
        // Wait, slide by one text and gap (the second copy then sits where the first began), repeat.
        let distance = textWidth + marqueeGap
        let travel = CFTimeInterval(distance / marqueeSpeed)
        let slide = CAKeyframeAnimation(keyPath: "transform.translation.x")
        slide.values = [0, 0, -distance]
        slide.keyTimes = [0, NSNumber(value: marqueePauseSeconds / (marqueePauseSeconds + travel)), 1]
        slide.duration = marqueePauseSeconds + travel
        slide.repeatCount = .infinity
        strip.add(slide, forKey: "marquee")
    }
}

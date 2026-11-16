// Caption bubbles next to the assistant's avatar: what the user says and what the assistant answers,
// shown while the words are spoken and faded out a few seconds later, like subtitles.
//
// The words come from two files next to the app. Each lives only while its words are in flight;
// the avatar keeps the text in memory until the bubbles fade. Only the user can read them.
//   caption-user.txt  assistant_listen (live while the user talks), then say_to_assistant.sh (what was sent)
//   caption-bot.txt   voice.py while the assistant speaks, talk.sh while the greeting plays
//
// The bubbles sit under the photo when there is room, otherwise beside it, toward the middle of
// the screen. They never take clicks. The menu turns them off ("Show captions").

import AppKit

let captionWidth: CGFloat = 300
// The bubbles grow to show the whole text up to these many lines; longer text scrolls smoothly
// inside, its oldest lines fading out at the top edge.
let captionUserMaxLines = 6
let captionBotMaxLines = 10
let captionScrollSeconds: TimeInterval = 0.25
let captionScrollFade: CGFloat = 14
let captionFont = NSFont.systemFont(ofSize: 13)
let captionPadding = NSSize(width: 12, height: 8)
let captionGap: CGFloat = 8
// Space between the photo and the bubbles, enough for the state label shown under the photo.
let captionDistance: CGFloat = 44
let captionCornerRadius: CGFloat = 13
// The reply fills in at about the pace of speech, and shows whole once the voice stops.
// Measured in spoken beats: a Hangul syllable is one beat, and English letters, spaces and marks are
// lighter (English speech runs about 15 letters a second, Korean about 7 syllables), so a reply in
// either language, or a mix, keeps up with the voice.
let captionRevealBeatsPerSecond: Double = 7
let captionLightCharacterBeats: Double = 0.45

func spokenBeats(_ character: Character) -> Double {
    let isHangul = character.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) || (0x3131...0x318E).contains($0.value) }
    return isHangul ? 1 : captionLightCharacterBeats
}

/// The beginning of the text that is said within this many beats (at least its first character).
func revealedPrefix(_ text: String, beats: Double) -> String {
    var used = 0.0
    var count = 0
    for character in text {
        used += spokenBeats(character)
        if used > beats && count > 0 { break }
        count += 1
    }
    return String(text.prefix(count))
}
let captionLingerSeconds: TimeInterval = 5
let captionFadeSeconds: TimeInterval = 0.6
let captionAppearSeconds: TimeInterval = 0.2
// The user's words with no reply yet fade after this; a reply whose voice never starts shows after the other.
let captionUnansweredSeconds: TimeInterval = 90
// Words still waiting for a reply when the conversation ends fade this soon after.
let captionClosedLingerSeconds: TimeInterval = 2
// With the pointer on a bubble it does not fade; after the pointer leaves, it waits this long first.
let captionHoverGraceSeconds: TimeInterval = 2
// A mouse wheel gives lines, a trackpad gives points.
let captionWheelLinePoints: CGFloat = 10
let captionUnstartedSeconds: TimeInterval = 4
// Files older than this when the avatar first sees them are left from an earlier conversation.
let captionStaleSeconds: TimeInterval = 120
let captionsShownDefaultsKey = "captionsShown"

enum CaptionColors {
    static let userFill = NSColor(calibratedWhite: 0.96, alpha: 0.94)
    static let userInk = NSColor(calibratedRed: 0.11, green: 0.10, blue: 0.17, alpha: 1)
    static let botFill = NSColor(calibratedRed: 0.19, green: 0.15, blue: 0.33, alpha: 0.92)
    static let botEdge = NSColor(calibratedRed: 0.70, green: 0.60, blue: 1.00, alpha: 0.45)
    static let botInk = NSColor.white
}

func captionsShown() -> Bool {
    UserDefaults.standard.object(forKey: captionsShownDefaultsKey) as? Bool ?? true
}

struct CaptionLine: Equatable {
    let text: String
    let arrived: TimeInterval
}

// What the bubbles show, worked out from the caption files and whether the assistant's voice plays.
// A value type with no AppKit in it, checked by tests/avatar_logic_test.swift.
struct CaptionBoard: Equatable {
    var user: CaptionLine?
    var bot: CaptionLine?
    var botStarted: TimeInterval?
    var botEnded: TimeInterval?
    var closedAt: TimeInterval?
    var heldUntil: TimeInterval?

    static let empty = CaptionBoard()

    var isEmpty: Bool { user == nil && bot == nil }

    // New words from the user start a new exchange.
    func heardUser(_ text: String, at now: TimeInterval) -> CaptionBoard {
        CaptionBoard(user: CaptionLine(text: text, arrived: now))
    }

    // A reply keeps the words it answers; a second reply in a row (a report, a follow-up) stands alone.
    func heardBot(_ text: String, at now: TimeInterval) -> CaptionBoard {
        CaptionBoard(user: bot == nil ? user : nil, bot: CaptionLine(text: text, arrived: now))
    }

    /// voicePending: voice.py is still making or waiting to play the voice (speech-queue/). The
    /// reply then waits for it however long it takes; only a reply with no voice coming shows
    /// after captionUnstartedSeconds.
    func ticked(speaking: Bool, voicePending: Bool = false, conversationOpen: Bool = true, at now: TimeInterval) -> CaptionBoard {
        var next = self
        if !conversationOpen, bot == nil, user != nil, closedAt == nil {
            next.closedAt = now
        }
        if let bot, botStarted == nil, speaking || (!voicePending && now - bot.arrived >= captionUnstartedSeconds) {
            next.botStarted = now
        }
        if botStarted != nil, botEnded == nil, !speaking {
            next.botEnded = now
        }
        if let fadeStart = next.fadeStart, now >= fadeStart + captionFadeSeconds {
            return .empty
        }
        return next
    }

    /// The pointer is on the bubbles: they stay until a little after it leaves.
    func holding(at now: TimeInterval) -> CaptionBoard {
        var next = self
        next.heldUntil = now + captionHoverGraceSeconds
        return next
    }

    var fadeStart: TimeInterval? {
        guard let planned = plannedFadeStart else { return nil }
        return max(planned, heldUntil ?? planned)
    }

    private var plannedFadeStart: TimeInterval? {
        if let botEnded { return botEnded + captionLingerSeconds }
        if bot == nil, let user {
            let unanswered = user.arrived + captionUnansweredSeconds
            return closedAt.map { min(unanswered, $0 + captionClosedLingerSeconds) } ?? unanswered
        }
        return nil
    }

    func opacity(at now: TimeInterval) -> Double {
        guard let fadeStart else { return 1 }
        return min(1, max(0, 1 - (now - fadeStart) / captionFadeSeconds))
    }

    // nil until the assistant's voice starts.
    func botShown(at now: TimeInterval) -> String? {
        guard let bot, let botStarted else { return nil }
        if botEnded != nil { return bot.text }
        return revealedPrefix(bot.text, beats: (now - botStarted) * captionRevealBeatsPerSecond)
    }
}

// Korean wraps between words (at spaces) instead of inside a word.
let captionLineBreaks: NSParagraphStyle.LineBreakStrategy = [.pushOut, .hangulWordPriority]

func makeCaptionField() -> NSTextField {
    let field = NSTextField(wrappingLabelWithString: "")
    field.font = captionFont
    field.lineBreakStrategy = captionLineBreaks
    field.isSelectable = false
    return field
}

// Measures text the same way the bubbles draw it.
final class CaptionMeasure {
    private let field = makeCaptionField()

    func size(_ text: String, width: CGFloat) -> NSSize {
        field.stringValue = text
        return field.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude)) ?? .zero
    }

    func height(lines: Int, width: CGFloat) -> CGFloat {
        size(Array(repeating: "가", count: max(lines, 1)).joined(separator: "\n"), width: width).height
    }
}

let captionMeasure = CaptionMeasure()
let captionInnerWidth = captionWidth - captionPadding.width * 2

// One bubble. It grows with its text; past its largest size the text scrolls up inside it so the
// newest line stays in view, and the lines above fade out at the top edge.
final class CaptionBubble: NSView {
    private let textClip = NSView()
    private let field = makeCaptionField()
    private let fade = CAGradientLayer()
    private let maxTextHeight: CGFloat
    private var visibleHeight: CGFloat = 0
    private var fullHeight: CGFloat = 0
    private(set) var shownText = ""
    private(set) var isScrolled = false
    // How far the text is scrolled back from its newest line, by hand.
    private(set) var scrollOffset: CGFloat = 0
    var maxScrollOffset: CGFloat { max(0, fullHeight - visibleHeight) }

    init(fromUser: Bool) {
        maxTextHeight = captionMeasure.height(lines: fromUser ? captionUserMaxLines : captionBotMaxLines, width: captionInnerWidth)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = captionCornerRadius
        layer?.backgroundColor = (fromUser ? CaptionColors.userFill : CaptionColors.botFill).cgColor
        layer?.borderWidth = fromUser ? 0 : 1
        layer?.borderColor = CaptionColors.botEdge.cgColor
        field.textColor = fromUser ? CaptionColors.userInk : CaptionColors.botInk
        textClip.wantsLayer = true
        textClip.layer?.masksToBounds = true
        fade.colors = [NSColor.clear.cgColor, NSColor.black.cgColor, NSColor.black.cgColor]
        fade.startPoint = CGPoint(x: 0.5, y: 1)
        fade.endPoint = CGPoint(x: 0.5, y: 0)
        textClip.addSubview(field)
        addSubview(textClip)
    }

    required init?(coder: NSCoder) { nil }

    static func maxHeight(fromUser: Bool) -> CGFloat {
        captionMeasure.height(lines: fromUser ? captionUserMaxLines : captionBotMaxLines, width: captionInnerWidth)
            + captionPadding.height * 2
    }

    // Shows the whole text and returns the bubble's size. With follow (the pointer is not on the
    // bubble) the newest line stays in view; without it, the lines being read stay where they are.
    func show(_ text: String, follow: Bool = true) -> NSSize {
        let textSize = captionMeasure.size(text, width: captionInnerWidth)
        let width = ceil(textSize.width)
        let growth = ceil(textSize.height) - fullHeight
        fullHeight = ceil(textSize.height)
        visibleHeight = min(fullHeight, ceil(maxTextHeight))
        let scrolling = fullHeight > visibleHeight
        let changed = text != shownText
        let returning = follow && scrollOffset > 0
        scrollOffset = follow ? 0 : min(max(scrollOffset + max(growth, 0), 0), maxScrollOffset)
        shownText = text
        field.stringValue = text
        textClip.frame = NSRect(x: captionPadding.width, y: captionPadding.height, width: width, height: visibleHeight)
        // Bottom-aligned in the clip (not flipped): the newest line sits at the bottom and older ones
        // rise above the top edge; scrolling back moves the text down. Following new words, and
        // coming back to the newest line, are animated like a scroll.
        let target = NSRect(x: 0, y: -scrollOffset, width: width, height: fullHeight)
        if scrolling && follow && ((isScrolled && changed) || returning) {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = captionScrollSeconds
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                field.animator().frame = target
            }
        } else {
            field.frame = target
        }
        isScrolled = scrolling
        updateFade(width: width)
        return NSSize(width: width + captionPadding.width * 2, height: visibleHeight + captionPadding.height * 2)
    }

    /// Scrolls back toward the first line (positive) or forward to the newest (negative).
    func scroll(by points: CGFloat) {
        scrollOffset = min(max(scrollOffset + points, 0), maxScrollOffset)
        field.frame.origin.y = -scrollOffset
        updateFade(width: textClip.frame.width)
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * captionWheelLinePoints
        scroll(by: delta)
    }

    // Fades the edge where more text is hidden: the top while earlier lines are above, the bottom
    // while it is scrolled back from the newest line.
    private func updateFade(width: CGFloat) {
        let hiddenAbove = maxScrollOffset - scrollOffset > 0.5
        let hiddenBelow = scrollOffset > 0.5
        guard visibleHeight > 0, hiddenAbove || hiddenBelow else {
            textClip.layer?.mask = nil
            return
        }
        let edge = NSNumber(value: Double(min(captionScrollFade / visibleHeight, 0.4)))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fade.frame = CGRect(x: 0, y: 0, width: width, height: visibleHeight)
        fade.colors = [hiddenAbove ? NSColor.clear.cgColor : NSColor.black.cgColor, NSColor.black.cgColor,
                       NSColor.black.cgColor, hiddenBelow ? NSColor.clear.cgColor : NSColor.black.cgColor]
        fade.locations = [0, edge, NSNumber(value: 1 - edge.doubleValue), 1]
        CATransaction.commit()
        textClip.layer?.mask = fade
    }
}

final class CaptionStack: NSView {
    private let userBubble = CaptionBubble(fromUser: true)
    private let botBubble = CaptionBubble(fromUser: false)

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(userBubble)
        addSubview(botBubble)
    }

    required init?(coder: NSCoder) { nil }

    static var maxHeight: CGFloat {
        CaptionBubble.maxHeight(fromUser: true) + captionGap + CaptionBubble.maxHeight(fromUser: false)
    }

    /// Whether the point (in this view) is on a shown bubble.
    func bubbleContains(_ point: NSPoint) -> Bool {
        [userBubble, botBubble].contains { !$0.isHidden && $0.frame.contains(point) }
    }

    // The user's words on the right, the assistant's on the left, top to bottom. Returns the height used.
    func show(user: String?, bot: String?, follow: Bool) -> CGFloat {
        var top: CGFloat = 0
        for (bubble, text, alignRight) in [(userBubble, user, true), (botBubble, bot, false)] {
            guard let text, !text.isEmpty else {
                bubble.isHidden = true
                continue
            }
            bubble.isHidden = false
            let size = bubble.show(text, follow: follow)
            bubble.frame = NSRect(x: alignRight ? captionWidth - size.width : 0, y: top, width: size.width, height: size.height)
            top += size.height + captionGap
        }
        return max(0, top - captionGap)
    }
}

final class Captions {
    private let userFile: URL
    private let botFile: URL
    private let panel: NSPanel
    private let stack = CaptionStack(frame: NSRect(x: 0, y: 0, width: captionWidth, height: CaptionStack.maxHeight))
    private var board = CaptionBoard.empty
    private var seen: [URL: Date] = [:]
    private var fading = false

    init(folder: URL) {
        userFile = folder.appendingPathComponent("caption-user.txt")
        botFile = folder.appendingPathComponent("caption-bot.txt")
        panel = NSPanel(contentRect: stack.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.contentView = stack
    }

    // Called on every avatar tick with the photo's place on screen. With the avatar hidden from
    // the menu bar menu, the bubbles hide too (they would float next to nothing).
    func update(speaking: Bool, voicePending: Bool, photo: NSRect, avatarShown: Bool, conversationOpen: Bool) {
        let now = Date().timeIntervalSince1970
        if let text = newText(in: userFile) { board = board.heardUser(text, at: now) }
        if let text = newText(in: botFile) { board = board.heardBot(text, at: now) }
        let hovering = pointerOnBubble()
        if hovering { board = board.holding(at: now) }
        board = board.ticked(speaking: speaking, voicePending: voicePending, conversationOpen: conversationOpen, at: now)
        // The panel takes the mouse only while the pointer is on a bubble (to scroll it by hand);
        // otherwise clicks go through to the window below.
        panel.ignoresMouseEvents = !hovering
        guard captionsShown(), avatarShown, !board.isEmpty else {
            hide()
            return
        }
        let height = stack.show(user: board.user?.text, bot: board.botShown(at: now), follow: !hovering)
        guard height > 0 else {
            hide()
            return
        }
        panel.setFrame(frame(height: height, photo: photo), display: true)
        updateFade(at: now)
    }

    /// Moves the bubbles along while the avatar is dragged, between ticks, so they keep up with it.
    func follow(photo: NSRect) {
        guard panel.isVisible else { return }
        panel.setFrame(frame(height: panel.frame.height, photo: photo), display: false)
    }

    // Fading is handed to the window server once, so it runs at the screen's frame rate instead of
    // at this 10-per-second tick.
    private func updateFade(at now: TimeInterval) {
        if let fadeStart = board.fadeStart, now >= fadeStart {
            guard !fading else { return }
            fading = true
            animateAlpha(to: 0, seconds: max(fadeStart + captionFadeSeconds - now, 0.05))
            return
        }
        guard fading || !panel.isVisible else { return }
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
        }
        fading = false
        animateAlpha(to: 1, seconds: captionAppearSeconds)
    }

    private func animateAlpha(to value: CGFloat, seconds: TimeInterval) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = seconds
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = value
        }
    }

    private func hide() {
        fading = false
        panel.ignoresMouseEvents = true
        panel.orderOut(nil)
    }

    private func pointerOnBubble() -> Bool {
        guard panel.isVisible, panel.alphaValue > 0 else { return false }
        let mouse = NSEvent.mouseLocation
        guard panel.frame.contains(mouse) else { return false }
        let inWindow = NSPoint(x: mouse.x - panel.frame.minX, y: mouse.y - panel.frame.minY)
        return stack.bubbleContains(stack.convert(inWindow, from: nil))
    }

    // Text written since the last look; nil when the file is missing, unchanged, empty or stale.
    private func newText(in file: URL) -> String? {
        guard let modified = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date,
              modified != seen[file] else { return nil }
        seen[file] = modified
        guard Date().timeIntervalSince(modified) < captionStaleSeconds,
              let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // Under the photo when the tallest bubbles fit there, otherwise beside it toward the middle of
    // the screen. Decided by the tallest size so the bubbles do not jump while a reply fills in.
    private func frame(height: CGFloat, photo: NSRect) -> NSRect {
        let screen = NSScreen.screens.first { $0.frame.intersects(photo) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? photo.insetBy(dx: -captionWidth, dy: -CaptionStack.maxHeight)
        let top = photo.minY - captionDistance
        if top - CaptionStack.maxHeight >= visible.minY {
            let x = min(max(photo.midX - captionWidth / 2, visible.minX), visible.maxX - captionWidth)
            return NSRect(x: x, y: top - height, width: captionWidth, height: height)
        }
        let toLeft = photo.midX > visible.midX
        let x = toLeft ? photo.minX - captionGap * 2 - captionWidth : photo.maxX + captionGap * 2
        let y = min(max(photo.minY, visible.minY), visible.maxY - height)
        return NSRect(x: x, y: y, width: captionWidth, height: height)
    }
}

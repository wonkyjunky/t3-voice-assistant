// The "now playing" card next to the avatar: one row for each place with music (YouTube in Chrome,
// the Music app), so music and a video watched at the same time each have their own controls. A
// row shows the song, where it plays, buttons to play or pause, skip and go back (Music), and a
// slider for that place's own volume (not the Mac's, so the assistant's voice keeps its level). A row stays while its music plays and for a while
// after it is paused; the card fades out when no row is left. What plays comes from
// avatar_nowplaying.swift.
//
// Dragging the card by its background takes it off the avatar and leaves it where it is dropped
// (saved, so it stays there); a double-click, "Attach now playing to avatar" or "Move to top right"
// in the menu puts it back beside the avatar.
//
// A button runs mac_control.py, the same fixed command the assistant uses, so the card can do
// nothing the assistant cannot; it controls only its own row's place. The card changes right away and the next
// check confirms it.

import AppKit

let nowPlayingWidth: CGFloat = 300
// One row: the song line on top, the volume line below it.
let nowPlayingRowHeight: CGFloat = 84
let nowPlayingTopHeight: CGFloat = 56
let nowPlayingGap: CGFloat = 16
let nowPlayingFadeSeconds: TimeInterval = 0.3
let nowPlayingButtonSize: CGFloat = 26
let nowPlayingButtonGap: CGFloat = 2
let nowPlayingSideMargin: CGFloat = 10
// After a button, the next check comes this soon, to show what the player really did.
let nowPlayingRecheckSeconds: TimeInterval = 0.6
// After a slider moves, checks keep its level this long (an answer asked before may be older).
let volumeHoldSeconds: TimeInterval = 2.5
let macControlPython = "/opt/homebrew/bin/python3"
// Where the card's top left corner was left. (The older key held the bottom left corner of a card
// that had one height only; it is dropped when the card is put back.)
let nowPlayingTopLeftDefaultsKey = "nowPlayingTopLeft"
let oldNowPlayingOriginDefaultsKey = "nowPlayingOrigin"
let cardDragThreshold: CGFloat = 3

func cardHeight(rows: Int) -> CGFloat {
    CGFloat(max(rows, 1)) * nowPlayingRowHeight
}

/// Where the card's top left corner was left when it was taken off the avatar, or nil while it
/// sits beside the avatar.
func detachedNowPlayingTopLeft() -> NSPoint? {
    guard let saved = UserDefaults.standard.string(forKey: nowPlayingTopLeftDefaultsKey) else { return nil }
    let topLeft = NSPointFromString(saved)
    let firstRow = NSRect(x: topLeft.x, y: topLeft.y - nowPlayingRowHeight, width: nowPlayingWidth, height: nowPlayingRowHeight)
    // A screen that is gone (an unplugged display) puts the card back on the avatar.
    return NSScreen.screens.contains { $0.visibleFrame.intersects(firstRow) } ? topLeft : nil
}

func attachNowPlayingToAvatar() {
    UserDefaults.standard.removeObject(forKey: nowPlayingTopLeftDefaultsKey)
    UserDefaults.standard.removeObject(forKey: oldNowPlayingOriginDefaultsKey)
}

/// A button that works on the first click even though the avatar app never becomes active.
final class CardButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// A slider that works on the first click too.
final class CardSlider: NSSlider {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

func symbolName(for control: NowPlayingControl, isPlaying: Bool) -> String {
    switch control {
    case .previous: return "backward.fill"
    case .playPause: return isPlaying ? "pause.fill" : "play.fill"
    case .next: return "forward.fill"
    }
}

/// One place's row: badge, song, buttons and volume slider. Clicks on its background go on to the
/// card, which moves.
final class NowPlayingRow: NSView {
    var onControl: ((NowPlayingControl, NowPlaying) -> Void)?
    var onVolume: ((Int, NowPlaying) -> Void)?
    private(set) var shown: NowPlaying?
    private let volumeSlider = CardSlider(value: 50, minValue: 0, maxValue: 100, target: nil, action: nil)
    private let badge = CALayer()
    private let badgeText = NSTextField(labelWithString: "▶")
    private let titleField = NSTextField(labelWithString: "")
    private let detailField = NSTextField(labelWithString: "")
    private var bars: [CALayer] = []
    private var buttons: [(NowPlayingControl, CardButton)] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        let top = frame.height - nowPlayingTopHeight
        badge.frame = CGRect(x: 12, y: top + (nowPlayingTopHeight - 24) / 2, width: 34, height: 24)
        badge.cornerRadius = 7
        layer?.addSublayer(badge)
        badgeText.frame = NSRect(x: 12, y: top + (nowPlayingTopHeight - 16) / 2, width: 34, height: 16)
        badgeText.alignment = .center
        badgeText.font = .systemFont(ofSize: 11, weight: .bold)
        badgeText.textColor = .white
        addSubview(badgeText)
        for (field, y, font, color) in [(titleField, 28.0, NSFont.systemFont(ofSize: 12, weight: .semibold), NSColor.white),
                                        (detailField, 11.0, NSFont.systemFont(ofSize: 11), NSColor(calibratedWhite: 1, alpha: 0.6))] {
            field.frame = NSRect(x: 56, y: top + y, width: 100, height: 16)
            field.font = font
            field.textColor = color
            field.lineBreakMode = .byTruncatingTail
            addSubview(field)
        }
        setUpBars()
        setUpVolumeLine(height: top)
    }

    required init?(coder: NSCoder) { nil }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // 🔈 ━━━●━━━ 🔊 under the song line.
    private func setUpVolumeLine(height: CGFloat) {
        let iconSize: CGFloat = 16
        let middle = height / 2 + 2
        for (name, x) in [("speaker.fill", 16.0), ("speaker.wave.3.fill", bounds.width - 16 - iconSize)] {
            let icon = NSImageView(frame: NSRect(x: x, y: middle - iconSize / 2, width: iconSize, height: iconSize))
            icon.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
            icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
            icon.contentTintColor = NSColor(calibratedWhite: 1, alpha: 0.6)
            addSubview(icon)
        }
        let start = 16 + iconSize + 6
        volumeSlider.frame = NSRect(x: start, y: middle - 10, width: bounds.width - start * 2, height: 20)
        volumeSlider.controlSize = .small
        volumeSlider.isContinuous = true
        volumeSlider.trackFillColor = .white
        volumeSlider.target = self
        volumeSlider.action = #selector(volumeMoved(_:))
        addSubview(volumeSlider)
    }

    @objc private func volumeMoved(_ sender: NSSlider) {
        guard let shown else { return }
        onVolume?(Int(sender.doubleValue.rounded()), shown)
    }

    // Three bars that bounce like an equalizer inside the badge while music plays, each at its own
    // pace (Core Animation, no timer). A paused song shows its mark instead.
    private func setUpBars() {
        let speeds: [CFTimeInterval] = [0.45, 0.62, 0.38]
        for (index, speed) in speeds.enumerated() {
            let bar = CALayer()
            bar.anchorPoint = CGPoint(x: 0.5, y: 0)
            bar.frame = CGRect(x: badge.frame.midX - 8 + CGFloat(index) * 6, y: badge.frame.minY + 5, width: 3, height: 14)
            bar.cornerRadius = 1.5
            bar.backgroundColor = NSColor.white.cgColor
            let bounce = CABasicAnimation(keyPath: "transform.scale.y")
            bounce.fromValue = 0.25
            bounce.toValue = 1
            bounce.duration = speed
            bounce.autoreverses = true
            bounce.repeatCount = .infinity
            bounce.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            bar.add(bounce, forKey: "bounce")
            layer?.addSublayer(bar)
            bars.append(bar)
        }
    }

    func show(_ playing: NowPlaying) {
        shown = playing
        let color = playing.source == .music
            ? NSColor(calibratedRed: 0.99, green: 0.24, blue: 0.4, alpha: 1)
            : NSColor(calibratedRed: 1, green: 0.24, blue: 0.24, alpha: 1)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        badge.backgroundColor = color.cgColor
        bars.forEach { $0.isHidden = !playing.isPlaying }
        CATransaction.commit()
        badgeText.isHidden = playing.isPlaying
        badgeText.stringValue = playing.source == .music ? "♪" : "▶"
        titleField.stringValue = playing.title
        detailField.stringValue = playing.detail
        volumeSlider.isEnabled = playing.volume != nil
        if let volume = playing.volume, Int(volumeSlider.doubleValue.rounded()) != volume {
            volumeSlider.doubleValue = Double(volume)
        }
        layOutButtons(for: playing)
    }

    // The buttons sit at the right; the song's words take the room left between badge and buttons.
    private func layOutButtons(for playing: NowPlaying) {
        let wanted = controls(for: playing.source)
        if buttons.map(\.0) != wanted {
            buttons.forEach { $0.1.removeFromSuperview() }
            buttons = wanted.map { control in (control, makeButton(for: control)) }
        }
        var x = bounds.width - nowPlayingSideMargin
        for (control, button) in buttons.reversed() {
            x -= nowPlayingButtonSize
            button.frame = NSRect(x: x, y: bounds.height - nowPlayingTopHeight + (nowPlayingTopHeight - nowPlayingButtonSize) / 2,
                                  width: nowPlayingButtonSize, height: nowPlayingButtonSize)
            button.image = NSImage(systemSymbolName: symbolName(for: control, isPlaying: playing.isPlaying),
                                   accessibilityDescription: nil)
            x -= nowPlayingButtonGap
        }
        let wordsWidth = max(0, x - 6 - titleField.frame.minX)
        for field in [titleField, detailField] {
            field.frame.size.width = wordsWidth
        }
    }

    private func makeButton(for control: NowPlayingControl) -> CardButton {
        let button = CardButton(frame: .zero)
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        button.contentTintColor = .white
        button.target = self
        button.action = #selector(pressed(_:))
        addSubview(button)
        return button
    }

    @objc private func pressed(_ sender: NSButton) {
        guard let shown, let control = buttons.first(where: { $0.1 === sender })?.0 else { return }
        onControl?(control, shown)
    }
}

/// The card: a rounded dark background with the rows stacked from the top, a thin line between
/// them. Its background moves it; a double-click puts it back beside the avatar.
final class NowPlayingCardView: NSView {
    var onControl: ((NowPlayingControl, NowPlaying) -> Void)?
    var onVolume: ((Int, NowPlaying) -> Void)?
    private(set) var isDragging = false
    private var dragStartMouse = NSPoint.zero
    private var dragStartOrigin = NSPoint.zero
    private var rows: [NowPlayingRow] = []
    private var separators: [CALayer] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.backgroundColor = NSColor(calibratedWhite: 0, alpha: 0.6).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(calibratedWhite: 1, alpha: 0.14).cgColor
    }

    required init?(coder: NSCoder) { nil }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Shows one row per song, top to bottom; the view's height must already fit them.
    func show(_ songs: [NowPlaying]) {
        while rows.count < songs.count {
            let row = NowPlayingRow(frame: NSRect(x: 0, y: 0, width: nowPlayingWidth, height: nowPlayingRowHeight))
            row.onControl = { [weak self] control, song in self?.onControl?(control, song) }
            row.onVolume = { [weak self] level, song in self?.onVolume?(level, song) }
            addSubview(row)
            rows.append(row)
        }
        while rows.count > songs.count {
            rows.removeLast().removeFromSuperview()
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        separators.forEach { $0.removeFromSuperlayer() }
        separators = []
        for (index, song) in songs.enumerated() {
            let top = bounds.height - CGFloat(index) * nowPlayingRowHeight
            rows[index].frame.origin = NSPoint(x: 0, y: top - nowPlayingRowHeight)
            rows[index].show(song)
            if index > 0 {
                let line = CALayer()
                line.frame = CGRect(x: 12, y: top, width: bounds.width - 24, height: 1)
                line.backgroundColor = NSColor(calibratedWhite: 1, alpha: 0.12).cgColor
                layer?.addSublayer(line)
                separators.append(line)
            }
        }
        CATransaction.commit()
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            attachNowPlayingToAvatar()
            return
        }
        dragStartMouse = NSEvent.mouseLocation
        dragStartOrigin = window?.frame.origin ?? .zero
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        let mouse = NSEvent.mouseLocation
        let dx = mouse.x - dragStartMouse.x
        let dy = mouse.y - dragStartMouse.y
        if hypot(dx, dy) > cardDragThreshold { isDragging = true }
        guard isDragging else { return }
        window?.setFrameOrigin(NSPoint(x: dragStartOrigin.x + dx, y: dragStartOrigin.y + dy))
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        isDragging = false
        if let frame = window?.frame {
            UserDefaults.standard.set(NSStringFromPoint(NSPoint(x: frame.minX, y: frame.maxY)), forKey: nowPlayingTopLeftDefaultsKey)
        }
    }
}

final class NowPlayingCard {
    private let panel: NSPanel
    private let view = NowPlayingCardView(frame: NSRect(x: 0, y: 0, width: nowPlayingWidth, height: nowPlayingRowHeight))
    private let folder: URL
    // Every place with music, as last heard (or as a button just changed it).
    private var songs: [NowPlaying] = []
    private var lastPlayingAt: [NowPlayingSource: Date] = [:]
    private var checking = false
    private var lastCheck = Date.distantPast
    private var visible = false
    // Bumped by each button press, so an answer asked for before the press cannot undo it.
    private var generation = 0
    // Per place: the slider's level and until when checks keep it; the newest level waiting to be sent.
    private var heldVolumes: [NowPlayingSource: (level: Int, until: Date)] = [:]
    private var pendingVolumes: [NowPlayingSource: Int] = [:]
    private var sendingVolume: Set<NowPlayingSource> = []

    init(folder: URL) {
        self.folder = folder
        panel = NSPanel(contentRect: view.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.contentView = view
        view.onControl = { [weak self] control, song in self?.press(control, on: song) }
        view.onVolume = { [weak self] level, song in self?.slide(to: level, on: song) }
    }

    private var rows: [NowPlaying] {
        visibleRows(songs, lastPlayingAt: lastPlayingAt, now: Date())
    }

    /// Called on every avatar tick with the photo's place on screen.
    func update(photo: NSRect, avatarShown: Bool) {
        if !checking && Date().timeIntervalSince(lastCheck) >= nowPlayingCheckSeconds { check() }
        render(photo: photo, avatarShown: avatarShown)
    }

    private func render(photo: NSRect?, avatarShown: Bool = true) {
        let rows = self.rows
        guard nowPlayingShown(), avatarShown, !rows.isEmpty else {
            hide()
            return
        }
        if !view.isDragging {
            let height = cardHeight(rows: rows.count)
            let origin = photo.map { self.origin(next: $0, height: height) }
                ?? NSPoint(x: panel.frame.minX, y: panel.frame.maxY - height)
            panel.setFrame(NSRect(x: origin.x, y: origin.y, width: nowPlayingWidth, height: height), display: false)
        }
        view.show(rows)
        show()
    }

    /// Moves the card along while the avatar is dragged, between ticks (not when it was set apart).
    func follow(photo: NSRect) {
        guard visible, detachedNowPlayingTopLeft() == nil else { return }
        panel.setFrameOrigin(origin(next: photo, height: panel.frame.height))
    }

    private func check() {
        checking = true
        lastCheck = Date()
        let folder = self.folder
        let asked = generation
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let found = everythingPlaying(folder: folder)
            DispatchQueue.main.async {
                guard let self else { return }
                self.checking = false
                if asked == self.generation { self.heard(found) }
            }
        }
    }

    private func heard(_ found: [NowPlaying]) {
        let now = Date()
        songs = found.map { song in
            guard let held = heldVolumes[song.source], now < held.until else { return song }
            return song.with(volume: held.level)
        }
        for song in found where song.isPlaying {
            lastPlayingAt[song.source] = now
        }
        lastPlayingAt = lastPlayingAt.filter { source, _ in found.contains { $0.source == source } }
    }

    private func replace(_ song: NowPlaying) {
        songs = songs.map { $0.source == song.source ? song : $0 }
    }

    // The row shows the press at once (pause flips the button), runs the
    // command for that row's place only, then checks again soon.
    private func press(_ control: NowPlayingControl, on song: NowPlaying) {
        generation += 1
        let arguments = macControlArguments(for: control, on: song)
        switch control {
        case .playPause:
            replace(song.with(isPlaying: !song.isPlaying))
            if !song.isPlaying { lastPlayingAt[song.source] = Date() }
        case .previous, .next:
            break
        }
        render(photo: nil)
        let script = folder.appendingPathComponent("mac_control.py").path
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            runMacControl(script: script, arguments: arguments)
            DispatchQueue.main.async {
                self?.lastCheck = Date().addingTimeInterval(nowPlayingRecheckSeconds - nowPlayingCheckSeconds)
            }
        }
    }

    // The level shows at once; mac_control.py runs for the newest level, one run at a time per
    // place, so a fast drag sends a few commands instead of dozens.
    private func slide(to level: Int, on song: NowPlaying) {
        replace(song.with(volume: level))
        heldVolumes[song.source] = (level, Date().addingTimeInterval(volumeHoldSeconds))
        pendingVolumes[song.source] = level
        sendVolume(for: song.source)
    }

    private func sendVolume(for source: NowPlayingSource) {
        guard !sendingVolume.contains(source), let level = pendingVolumes[source],
              let song = songs.first(where: { $0.source == source }) else { return }
        pendingVolumes[source] = nil
        sendingVolume.insert(source)
        heldVolumes[source] = (level, Date().addingTimeInterval(volumeHoldSeconds))
        let arguments = macControlVolumeArguments(level, on: song)
        let script = folder.appendingPathComponent("mac_control.py").path
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            runMacControl(script: script, arguments: arguments)
            DispatchQueue.main.async {
                guard let self else { return }
                self.sendingVolume.remove(source)
                if let held = self.heldVolumes[source] {
                    self.heldVolumes[source] = (held.level, Date().addingTimeInterval(volumeHoldSeconds))
                }
                self.sendVolume(for: source)
            }
        }
    }

    // Beside the photo, toward the middle of the screen, its top level with the photo's top so it
    // stays clear of the caption bubbles below; or where it was left, its top staying put as rows
    // come and go.
    private func origin(next photo: NSRect, height: CGFloat) -> NSPoint {
        if let topLeft = detachedNowPlayingTopLeft() { return NSPoint(x: topLeft.x, y: topLeft.y - height) }
        let screen = NSScreen.screens.first { $0.frame.intersects(photo) } ?? NSScreen.main
        let middle = screen?.visibleFrame.midX ?? photo.midX
        let x = photo.midX > middle ? photo.minX - nowPlayingGap - nowPlayingWidth : photo.maxX + nowPlayingGap
        return NSPoint(x: x, y: photo.maxY - height)
    }

    private func show() {
        guard !visible else { return }
        visible = true
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = nowPlayingFadeSeconds
            panel.animator().alphaValue = 1
        }
    }

    private func hide() {
        guard visible else { return }
        visible = false
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = nowPlayingFadeSeconds
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, !self.visible else { return }
            self.panel.orderOut(nil)
        })
    }
}

/// Runs mac_control.py with fixed arguments and waits for it (off the main thread).
private func runMacControl(script: String, arguments: [String]) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: macControlPython)
    process.arguments = ["-I", script] + arguments
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        NSLog("now playing: could not run mac_control.py: \(error.localizedDescription)")
    }
}

// assistant_avatar: The assistant's round, animated face that stays in a screen corner.
//
// Plays a short looping clip for each state, with a quiet effect around it:
//   idle       no conversation: idle clip, no ring, only a soft shadow
//   waking     just clicked, the microphone is opening: idle clip, the glow lights up
//   greeting   the recorded greeting plays: greeting clip in step with the voice, the glow pulses
//   listening  the user's turn: listening clip, slowly turning glow that breathes, faint ripples
//   replying   the assistant is thinking: idle clip, the glow turns quickly
//   speaking   the assistant's voice is playing (speaking.pid or a `say` process): speaking clip, the glow
//              pulses like speech
// The glow is one style for every state: a hairline ring plus a blurred halo in soft pink, peach,
// lavender and sky colors. Hovering over the photo shows a small glass label with the state.
// The state comes from talk.state, written by talk.sh; speaking is detected directly.
//
// Scroll over the photo: bigger (up) or smaller (down); the size is remembered.
// Click: start a conversation, cut the assistant off while it speaks, or end the conversation
// (runs talk.sh). Drag: move it; the position is remembered.
// Right click: menu with the ElevenLabs characters left and "close".
// Clicks on the transparent space around the photo pass through to the window below.
//
// Files are found next to the app: avatar/idle.mp4, avatar/listening.mp4, avatar/speaking.mp4,
// avatar.png (shown when a clip is missing), talk.state and talk.sh.
// Caption bubbles with what is said (avatar_captions.swift) and sound bars that follow the voice
// (avatar_meter.swift) are drawn from the caption-*.txt and level-*.txt files next to the app.
// Only one copy runs; opening it again does nothing. Build with build_avatar.sh.

import AppKit
import AVFoundation
import CoreImage
import Darwin

let avatarSide: CGFloat = 240
let effectPadding: CGFloat = 70
let panelSide = avatarSide + effectPadding * 2
let screenMargin: CGFloat = 24
let tickSeconds: TimeInterval = 0.1
let dragThreshold: CGFloat = 3
let fadeSeconds: CFTimeInterval = 0.3
let positionDefaultsKey = "avatarOrigin"
let speechProcessName = "say"
// idle, listening and speaking are the base clips; thinking shows while the assistant prepares a reply;
// speaking_happy, speaking_sad and speaking_playful replace speaking when the reply's tag fits.
let clipNames = ["idle", "greeting", "listening", "speaking", "speaking_happy", "speaking_sad", "speaking_playful", "speaking_comfort", "thinking"]

// Glow around the photo: a crisp hairline ring and a blurred halo on the same circle.
let ringGap: CGFloat = 4
let crispLineWidth: CGFloat = 2.5
let haloLineWidth: CGFloat = 16
let haloBlurRadius: CGFloat = 14
let fullTurnSeconds: CFTimeInterval = 6

// Ripples while listening: thin, quiet and spaced out.
let rippleCount = 3
let rippleBeatSeconds: CFTimeInterval = 0.7
let rippleMaxScale: CGFloat = 1.32
let rippleLineWidth: CGFloat = 1.2
let rippleStartOpacity: Float = 0.55

// Glass label shown under the photo while the pointer is over it.
let labelSize = NSSize(width: 132, height: 26)
let labelGap: CGFloat = 10
let labelFadeSeconds: TimeInterval = 0.2

// Scrolling over the photo resizes the avatar around its centre; scale 1 is the size above.
let minAvatarScale: CGFloat = 0.5
let maxAvatarScale: CGFloat = 1.75
let scaleDefaultsKey = "avatarScale"
let preciseScrollStep: CGFloat = 0.004
let lineScrollStep: CGFloat = 0.06

enum Palette {
    static let pink = NSColor(calibratedRed: 0.98, green: 0.58, blue: 0.76, alpha: 1)
    static let peach = NSColor(calibratedRed: 1.00, green: 0.74, blue: 0.52, alpha: 1)
    static let lavender = NSColor(calibratedRed: 0.70, green: 0.56, blue: 1.00, alpha: 1)
    static let sky = NSColor(calibratedRed: 0.45, green: 0.78, blue: 1.00, alpha: 1)
    static let glow: [NSColor] = [pink, peach, lavender, sky, pink]
    static let ripple = NSColor(calibratedWhite: 1, alpha: 1)
    static let shadow = NSColor(calibratedWhite: 0, alpha: 1)
}

// How the glow behaves in one state. A halo range of 0...0 means no halo.
struct Look {
    let ringOpacity: Float
    let haloLow: Float
    let haloHigh: Float
    let breathSeconds: CFTimeInterval
    let turnSpeed: Float
    let ripples: Bool
}

enum AvatarState: String {
    case idle, waking, greeting, listening, replying, speaking

    var clipName: String {
        switch self {
        case .idle, .waking: return "idle"
        case .greeting: return "greeting"
        case .replying: return "thinking"
        case .listening: return "listening"
        case .speaking: return "speaking"
        }
    }

    var look: Look {
        switch self {
        case .idle:
            return Look(ringOpacity: 0, haloLow: 0, haloHigh: 0, breathSeconds: 1, turnSpeed: 1, ripples: false)
        case .listening:
            return Look(ringOpacity: 0.9, haloLow: 0.45, haloHigh: 0.85, breathSeconds: 1.2, turnSpeed: 1, ripples: true)
        case .replying:
            return Look(ringOpacity: 0.7, haloLow: 0.35, haloHigh: 0.7, breathSeconds: 0.9, turnSpeed: 4, ripples: false)
        case .waking:
            return Look(ringOpacity: 0.9, haloLow: 0.3, haloHigh: 0.6, breathSeconds: 0.8, turnSpeed: 2, ripples: false)
        case .greeting, .speaking:
            return Look(ringOpacity: 1, haloLow: 0.55, haloHigh: 1, breathSeconds: 0.35, turnSpeed: 2, ripples: false)
        }
    }

    var label: String {
        let name = ui(assistantEnglishName, assistantName)
        switch self {
        case .idle: return name
        case .waking, .greeting: return ui("\(name) · hello", "\(name) · 반가워")
        case .listening: return ui("\(name) · listening", "\(name) · 듣는 중")
        case .replying: return ui("\(name) · thinking", "\(name) · 생각 중")
        case .speaking: return ui("\(name) · speaking", "\(name) · 말하는 중")
        }
    }
}

struct AvatarFiles {
    let base = Bundle.main.bundleURL.deletingLastPathComponent()

    func clip(_ name: String) -> URL { base.appendingPathComponent("avatar/\(name).mp4") }
    var still: URL { base.appendingPathComponent("avatar.png") }
    var state: URL { base.appendingPathComponent("talk.state") }
    var talkScript: URL { base.appendingPathComponent("talk.sh") }
    var speakingMarker: URL { base.appendingPathComponent("speaking.pid") }
    var speakingStyle: URL { base.appendingPathComponent("speaking.style") }
    var name: URL { base.appendingPathComponent("assistant-name.txt") }
}

let files = AvatarFiles()

// The names on the hover label: assistant-name.txt, written by install.sh from assistant.conf,
// holds the Korean name on its first line and the English one on its second.
let assistantNames: [String] = ((try? String(contentsOf: files.name, encoding: .utf8)) ?? "")
    .split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
let assistantName = assistantNames.first ?? "비서"
let assistantEnglishName = assistantNames.dropFirst().first ?? (assistantNames.first ?? "Assistant")

// voice.py names its player in speaking.pid while the assistant's voice plays.
// voice.py lists each speech that is being made or waits to play in speech-queue/ (files named
// "<pid>-..."), so a slow voice still counts as coming.
func isVoiceQueued() -> Bool {
    let queue = files.base.appendingPathComponent("speech-queue")
    let names = (try? FileManager.default.contentsOfDirectory(atPath: queue.path)) ?? []
    return names.contains { name in
        guard let pid = pid_t(name.split(separator: "-").first ?? "") else { return false }
        return kill(pid, 0) == 0
    }
}

func isVoicePlaying() -> Bool {
    guard let raw = try? String(contentsOf: files.speakingMarker, encoding: .utf8),
          let pid = pid_t(raw.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
    return kill(pid, 0) == 0
}

func isSpeechPlaying() -> Bool {
    if isVoicePlaying() { return true }
    let capacity = Int(proc_listallpids(nil, 0)) + 64
    var pids = [pid_t](repeating: 0, count: capacity)
    let found = Int(proc_listallpids(&pids, Int32(capacity * MemoryLayout<pid_t>.size)))
    var name = [CChar](repeating: 0, count: 64)
    for pid in pids.prefix(max(found, 0)) where pid > 0 {
        if proc_name(pid, &name, UInt32(name.count)) > 0 && String(cString: name) == speechProcessName {
            return true
        }
    }
    return false
}

func currentState() -> AvatarState {
    if isSpeechPlaying() { return .speaking }
    let raw = (try? String(contentsOf: files.state, encoding: .utf8)) ?? ""
    return AvatarState(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines)) ?? .idle
}

// One line such as "남은 글자 150,000 / 156,736", from voice.py (it gives up after a few seconds).
func creditSummary() -> String {
    let unknown = ui("usage: could not check", "사용량: 확인 못 함")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/python3")
    process.arguments = ["-I", files.base.appendingPathComponent("voice.py").path, "usage", menuLanguage()]
    let output = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    do {
        try process.run()
    } catch {
        return unknown
    }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return text.isEmpty ? unknown : text
}

// The talk script ends a running conversation when started a second time, or only cuts
// The assistant off when it is speaking.
func toggleConversation() {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = [files.talkScript.path]
    do {
        try process.run()
    } catch {
        NSLog("assistant_avatar: cannot start the conversation script: \(error.localizedDescription)")
    }
}

func savePosition(_ origin: NSPoint) {
    UserDefaults.standard.set(NSStringFromPoint(origin), forKey: positionDefaultsKey)
}

// Keeps the photo inside the screen; the transparent effect space may hang over the edge.
func clamped(_ origin: NSPoint, into visible: NSRect) -> NSPoint {
    NSPoint(
        x: min(max(origin.x, visible.minX - effectPadding), visible.maxX - avatarSide - effectPadding),
        y: min(max(origin.y, visible.minY - effectPadding), visible.maxY - avatarSide - effectPadding)
    )
}

func initialOrigin() -> NSPoint {
    let screens = NSScreen.screens
    if let saved = UserDefaults.standard.string(forKey: positionDefaultsKey) {
        let origin = NSPointFromString(saved)
        let frame = NSRect(origin: origin, size: NSSize(width: panelSide, height: panelSide))
        if let screen = screens.first(where: { $0.visibleFrame.intersects(frame) }) {
            return clamped(origin, into: screen.visibleFrame)
        }
    }
    return cornerOrigin(scale: 1, in: (NSScreen.main ?? screens[0]).visibleFrame)
}

func circlePath(in rect: CGRect) -> CGPath {
    CGPath(ellipseIn: rect, transform: nil)
}

func forever(_ animation: CABasicAnimation, seconds: CFTimeInterval) -> CABasicAnimation {
    animation.duration = seconds
    animation.repeatCount = .infinity
    return animation
}

func spin(seconds: CFTimeInterval) -> CABasicAnimation {
    let animation = CABasicAnimation(keyPath: "transform.rotation.z")
    animation.fromValue = 0
    animation.toValue = -2 * CGFloat.pi
    return forever(animation, seconds: seconds)
}

final class ClipPlayer {
    let layer: AVPlayerLayer
    private let player: AVQueuePlayer
    private let looper: AVPlayerLooper

    init?(url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let player = AVQueuePlayer()
        player.isMuted = true
        self.player = player
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspectFill
    }

    // A clip shown for the first time in a state starts from its first frame, so it is seen
    // whole; when it comes back within the same state it carries on.
    func show(_ visible: Bool, fromStart: Bool) {
        if visible && layer.isHidden && fromStart { player.seek(to: .zero) }
        layer.isHidden = !visible
        if visible { player.play() } else { player.pause() }
    }
}

final class AvatarView: NSView {
    private let photoRect = CGRect(x: effectPadding, y: effectPadding, width: avatarSide, height: avatarSide)
    private let shadowLayer = CALayer()
    private let photoLayer = CALayer()
    private let rippleLayer = CAReplicatorLayer()
    private let crispRing = CAGradientLayer()
    private let haloContainer = CALayer()
    private let haloRing = CAGradientLayer()
    private let label = NSVisualEffectView()
    private let labelText = NSTextField(labelWithString: AvatarState.idle.label)
    private var clips: [String: ClipPlayer] = [:]
    private var shownState: AvatarState?
    private var shownClip: String?
    private var clipsStartedInState: Set<String> = []
    private var dragStartMouse = NSPoint.zero
    private var dragStartOrigin = NSPoint.zero
    private var dragged = false
    // Everything drawn sits in contentLayer at the base size; resizing scales it as one piece.
    private let contentLayer = CALayer()
    private var scale: CGFloat = 1
    let meter = VoiceMeter(folder: files.base,
                           photoRect: CGRect(x: effectPadding, y: effectPadding, width: avatarSide, height: avatarSide))

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerUsesCoreImageFilters = true
        layer?.masksToBounds = false
        contentLayer.frame = bounds
        layer?.addSublayer(contentLayer)
        setUpShadow()
        setUpHalo()
        setUpRipples()
        setUpPhoto()
        setUp(ring: crispRing, lineWidth: crispLineWidth, in: contentLayer)
        contentLayer.addSublayer(meter.layer)
        setUpLabel()
        for effect in [crispRing, haloContainer, rippleLayer] { effect.opacity = 0 }
    }

    required init?(coder: NSCoder) { nil }

    private func setUpShadow() {
        shadowLayer.frame = photoRect
        shadowLayer.shadowPath = circlePath(in: CGRect(origin: .zero, size: photoRect.size))
        shadowLayer.shadowColor = Palette.shadow.cgColor
        shadowLayer.shadowOpacity = 0.35
        shadowLayer.shadowRadius = 12
        shadowLayer.shadowOffset = CGSize(width: 0, height: -4)
        contentLayer.addSublayer(shadowLayer)
    }

    // The halo sits behind the photo, so only its outer half shows, softened by a blur.
    private func setUpHalo() {
        haloContainer.frame = bounds
        if let blur = CIFilter(name: "CIGaussianBlur", parameters: [kCIInputRadiusKey: haloBlurRadius]) {
            haloContainer.filters = [blur]
        }
        setUp(ring: haloRing, lineWidth: haloLineWidth, in: haloContainer)
        contentLayer.addSublayer(haloContainer)
    }

    // A ring on the circle just outside the photo, painted with the turning conic glow colors.
    private func setUp(ring: CAGradientLayer, lineWidth: CGFloat, in parent: CALayer?) {
        let ringRect = photoRect.insetBy(dx: -(ringGap + lineWidth), dy: -(ringGap + lineWidth))
        ring.frame = ringRect
        ring.type = .conic
        ring.startPoint = CGPoint(x: 0.5, y: 0.5)
        ring.endPoint = CGPoint(x: 0.5, y: 0)
        ring.colors = Palette.glow.map(\.cgColor)
        let mask = CAShapeLayer()
        mask.path = circlePath(in: CGRect(origin: .zero, size: ringRect.size).insetBy(dx: lineWidth, dy: lineWidth))
        mask.fillColor = nil
        mask.strokeColor = NSColor.black.cgColor
        mask.lineWidth = lineWidth
        ring.mask = mask
        ring.add(spin(seconds: fullTurnSeconds), forKey: "spin")
        parent?.addSublayer(ring)
    }

    private func setUpRipples() {
        rippleLayer.frame = bounds
        rippleLayer.instanceCount = rippleCount
        rippleLayer.instanceDelay = rippleBeatSeconds
        let ring = CAShapeLayer()
        ring.frame = bounds
        ring.path = circlePath(in: photoRect.insetBy(dx: -ringGap, dy: -ringGap))
        ring.fillColor = nil
        ring.strokeColor = Palette.ripple.cgColor
        ring.lineWidth = rippleLineWidth
        ring.opacity = 0

        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 1
        grow.toValue = rippleMaxScale
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = rippleStartOpacity
        fade.toValue = 0
        let beat = CAAnimationGroup()
        beat.animations = [grow, fade]
        beat.duration = rippleBeatSeconds * Double(rippleCount)
        beat.timingFunction = CAMediaTimingFunction(name: .easeOut)
        beat.repeatCount = .infinity
        ring.add(beat, forKey: "beat")
        rippleLayer.addSublayer(ring)
        contentLayer.addSublayer(rippleLayer)
    }

    private func setUpPhoto() {
        photoLayer.frame = photoRect
        photoLayer.cornerRadius = avatarSide / 2
        photoLayer.masksToBounds = true
        photoLayer.contents = NSImage(contentsOf: files.still)
        photoLayer.contentsGravity = .resizeAspectFill
        contentLayer.addSublayer(photoLayer)
        for name in clipNames {
            guard let clip = ClipPlayer(url: files.clip(name)) else { continue }
            clip.layer.frame = photoLayer.bounds
            clip.layer.isHidden = true
            photoLayer.addSublayer(clip.layer)
            clips[name] = clip
        }
    }

    // The photo's rectangle in the view at the current size.
    private var scaledPhotoRect: NSRect {
        let side = avatarSide * scale
        return NSRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
    }

    // The photo's rectangle on screen, for placing the caption bubbles.
    var photoOnScreen: NSRect {
        guard let window else { return .zero }
        return window.convertToScreen(convert(scaledPhotoRect, to: nil))
    }

    private func layoutLabel() {
        label.frame = NSRect(
            x: bounds.midX - labelSize.width / 2,
            y: scaledPhotoRect.minY - labelGap - labelSize.height,
            width: labelSize.width,
            height: labelSize.height
        )
    }

    /// Shows the hover label in the current menu language (after the language changes).
    func refreshLabel() {
        labelText.stringValue = (shownState ?? .idle).label
    }

    /// Resizes the avatar around its centre, keeping it between the smallest and largest size.
    func applyScale(_ requested: CGFloat, save: Bool) {
        scale = min(max(requested, minAvatarScale), maxAvatarScale)
        guard let window else { return }
        let side = panelSide * scale
        let center = NSPoint(x: window.frame.midX, y: window.frame.midY)
        window.setFrame(NSRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side), display: true)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentLayer.bounds = CGRect(x: 0, y: 0, width: panelSide, height: panelSide)
        contentLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        contentLayer.transform = CATransform3DMakeScale(scale, scale, 1)
        CATransaction.commit()
        layoutLabel()
        updateTrackingAreas()
        if save { UserDefaults.standard.set(Double(scale), forKey: scaleDefaultsKey) }
    }

    // Fingers or wheel moving up makes the avatar bigger, whatever the natural-scrolling setting is.
    override func scrollWheel(with event: NSEvent) {
        var delta = event.scrollingDeltaY
        if event.isDirectionInvertedFromDevice { delta = -delta }
        guard delta != 0 else { return }
        let step = event.hasPreciseScrollingDeltas ? preciseScrollStep : lineScrollStep
        applyScale(scale * exp(delta * step), save: true)
    }

    private func setUpLabel() {
        layoutLabel()
        label.material = .hudWindow
        label.blendingMode = .behindWindow
        label.state = .active
        label.wantsLayer = true
        label.layer?.cornerRadius = labelSize.height / 2
        label.layer?.masksToBounds = true
        label.alphaValue = 0
        labelText.font = .systemFont(ofSize: 12, weight: .medium)
        labelText.textColor = .white
        labelText.alignment = .center
        labelText.frame = label.bounds.insetBy(dx: 8, dy: 5)
        label.addSubview(labelText)
        addSubview(label)
    }

    // Changes how fast a ring turns without making it jump.
    private func setTurnSpeed(_ speed: Float, of ring: CALayer) {
        guard ring.speed != speed else { return }
        let now = CACurrentMediaTime()
        ring.timeOffset = ring.convertTime(now, from: nil)
        ring.beginTime = now
        ring.speed = speed
    }

    // While speaking, voice.py names the talking clip that fits the reply's mood (speaking.style).
    private func speakingStyleClip() -> String? {
        guard let raw = try? String(contentsOf: files.speakingStyle, encoding: .utf8) else { return nil }
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return clips[name] != nil ? name : nil
    }

    // The clip for a state, with the base clips standing in when a newer clip is missing.
    private func clipName(for state: AvatarState) -> String {
        if state == .speaking, let style = speakingStyleClip() { return style }
        let name = state.clipName
        if clips[name] != nil { return name }
        return state == .replying || state == .greeting ? "idle" : name
    }

    func show(_ state: AvatarState) {
        let clip = clipName(for: state)
        if state != shownState { clipsStartedInState.removeAll() }
        if clip != shownClip {
            shownClip = clip
            let fromStart = !clipsStartedInState.contains(clip)
            clipsStartedInState.insert(clip)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for (name, player) in clips { player.show(name == clip, fromStart: fromStart) }
            CATransaction.commit()
        }
        guard state != shownState else { return }
        shownState = state
        let look = state.look
        labelText.stringValue = state.label
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        setTurnSpeed(look.turnSpeed, of: crispRing)
        setTurnSpeed(look.turnSpeed, of: haloRing)
        CATransaction.commit()

        haloContainer.removeAnimation(forKey: "breath")
        CATransaction.begin()
        CATransaction.setAnimationDuration(fadeSeconds)
        crispRing.opacity = look.ringOpacity
        rippleLayer.opacity = look.ripples ? 1 : 0
        haloContainer.opacity = look.haloHigh
        CATransaction.commit()
        guard look.haloHigh > 0 else { return }
        let breath = CABasicAnimation(keyPath: "opacity")
        breath.fromValue = look.haloLow
        breath.toValue = look.haloHigh
        breath.autoreverses = true
        breath.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        haloContainer.add(forever(breath, seconds: look.breathSeconds), forKey: "breath")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: scaledPhotoRect, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { setLabelVisible(true) }
    override func mouseExited(with event: NSEvent) { setLabelVisible(false) }

    private func setLabelVisible(_ visible: Bool) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = labelFadeSeconds
            label.animator().alphaValue = visible ? 1 : 0
        }
    }

    // Only the round photo takes clicks.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        let photo = scaledPhotoRect
        return hypot(local.x - photo.midX, local.y - photo.midY) <= photo.width / 2 ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        dragStartMouse = NSEvent.mouseLocation
        dragStartOrigin = window?.frame.origin ?? .zero
        dragged = false
    }

    override func mouseDragged(with event: NSEvent) {
        let mouse = NSEvent.mouseLocation
        let dx = mouse.x - dragStartMouse.x
        let dy = mouse.y - dragStartMouse.y
        if hypot(dx, dy) > dragThreshold { dragged = true }
        guard dragged else { return }
        window?.setFrameOrigin(NSPoint(x: dragStartOrigin.x + dx, y: dragStartOrigin.y + dy))
    }

    override func mouseUp(with event: NSEvent) {
        guard dragged else {
            toggleConversation()
            return
        }
        // Saved as the base-size origin around the same centre, so a later size change keeps it.
        if let frame = window?.frame { savePosition(NSPoint(x: frame.midX - panelSide / 2, y: frame.midY - panelSide / 2)) }
    }

    // The same menu as the menu bar icon (avatar_menu.swift).
    override func rightMouseDown(with event: NSEvent) {
        avatarMenu.popUp(with: event, for: self)
    }
}

func makePanel(with view: NSView, at origin: NSPoint) -> NSPanel {
    let frame = NSRect(origin: origin, size: NSSize(width: panelSide, height: panelSide))
    let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.hidesOnDeactivate = false
    panel.contentView = view
    return panel
}

let otherCopies = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
    .filter { $0.processIdentifier != getpid() }
if !otherCopies.isEmpty { exit(0) }

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let avatarView = AvatarView(frame: NSRect(x: 0, y: 0, width: panelSide, height: panelSide))
let panel = makePanel(with: avatarView, at: initialOrigin())
// Hidden from the menu bar menu stays hidden; the menu bar icon and the shortcut still work.
if avatarShown() { panel.orderFrontRegardless() }
// The global key (⌃⌥C unless changed in the menu) works like a click on the avatar.
let hotkey = Hotkey(action: toggleConversation)
let avatarMenu = AvatarMenu(avatarView: avatarView, panel: panel, hotkey: hotkey)
let savedScale = UserDefaults.standard.double(forKey: scaleDefaultsKey)
avatarView.applyScale(savedScale > 0 ? CGFloat(savedScale) : 1, save: false)

extension MeterSource {
    init(state: AvatarState) {
        switch state {
        case .listening: self = .user
        case .greeting, .speaking: self = .bot
        case .idle, .waking, .replying: self = .none
        }
    }
}

let captions = Captions(folder: files.base)
var latestState = currentState()
avatarView.show(latestState)

Timer.scheduledTimer(withTimeInterval: tickSeconds, repeats: true) { _ in
    latestState = currentState()
    avatarView.show(latestState)
    avatarMenu.show(latestState)
    captions.update(speaking: MeterSource(state: latestState) == .bot, voicePending: isVoiceQueued(),
                    photo: avatarView.photoOnScreen,
                    avatarShown: avatarShown(), conversationOpen: conversationRunning())
}
// The bars move more often than the state is checked, so they follow the voice smoothly.
Timer.scheduledTimer(withTimeInterval: meterTickSeconds, repeats: true) { _ in
    avatarView.meter.update(source: meterShown() ? MeterSource(state: latestState) : .none)
}
app.run()

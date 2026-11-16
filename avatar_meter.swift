// Sound bars at the bottom of the avatar's photo that move with how loud the voice is:
//   while listening  the user's voice: level-user.txt from assistant_listen, one number about 25 times a second
//   while speaking   the assistant's voice: level-bot.txt from voice.py, the loudness of its reply worked out
//                    ahead of playback, one number per step, timed from when the player started
// With no numbers to follow (the greeting, the Yuna voice) the bars move on their own while it
// speaks. Only loudness numbers are read, never sound or words.

import AppKit

let meterBarCount = 7
let meterBarWidth: CGFloat = 5
let meterBarGap: CGFloat = 4
let meterMinBarHeight: CGFloat = 4
let meterMaxBarHeight: CGFloat = 26
// From the bottom of the photo to the foot of the bars.
let meterBottomInset: CGFloat = 26
let meterTickSeconds: TimeInterval = 1.0 / 30
// Taller in the middle.
let meterShape: [Double] = [0.45, 0.7, 0.9, 1, 0.9, 0.7, 0.45]
// Each tick a quieter voice keeps this much of the last level, so bars fall smoothly but rise at once.
let meterRelease = 0.82
let meterFadeSeconds: CFTimeInterval = 0.25
// The user's level file stops changing when the listener pauses or ends; older numbers count as silence.
let userLevelFreshSeconds: TimeInterval = 0.5
// The player takes about this long from starting to making the first sound (ffplay measured at
// 0.22 s with voice.py's MP3_FAST_START flags).
let playerStartSeconds: TimeInterval = 0.2

enum MeterColors {
    static let user = NSColor(calibratedRed: 0.72, green: 0.88, blue: 1.00, alpha: 0.95)
    static let bot = NSColor(calibratedWhite: 1, alpha: 0.95)
    static let shadow = NSColor(calibratedWhite: 0, alpha: 1)
}

enum MeterSource: Equatable {
    case none, user, bot
}

// The reply's loudness as voice.py writes it: "start <seconds since 1970> step <seconds> pid <n>",
// then one number from 0 to 1 per line.
struct LevelTrack: Equatable {
    let start: TimeInterval
    let step: TimeInterval
    let values: [Double]

    static func parse(_ text: String) -> LevelTrack? {
        let lines = text.split(separator: "\n")
        guard let header = lines.first else { return nil }
        let words = header.split(separator: " ")
        guard words.count >= 4, words[0] == "start", words[2] == "step",
              let start = Double(words[1]), let step = Double(words[3]), step > 0 else { return nil }
        return LevelTrack(start: start, step: step, values: lines.dropFirst().compactMap { Double($0) })
    }

    // The loudness sounding now: quiet before the first sound and after the last number.
    func level(at now: TimeInterval) -> Double {
        let position = (now - start - playerStartSeconds) / step
        guard position >= 0 else { return 0 }
        let index = Int(position)
        return index < values.count ? values[index] : 0
    }
}

func smoothedLevel(previous: Double, target: Double) -> Double {
    target >= previous ? target : max(target, previous * meterRelease)
}

// Each bar wobbles a little on its own so the row looks alive even when the level holds still.
func barHeights(level: Double, at time: TimeInterval) -> [CGFloat] {
    meterShape.enumerated().map { index, weight in
        let wobble = 0.75 + 0.25 * sin(time * 7 + Double(index) * 1.3)
        let share = CGFloat(min(1, max(0, level * weight * wobble)))
        return meterMinBarHeight + (meterMaxBarHeight - meterMinBarHeight) * share
    }
}

// The assistant's voice when no numbers come with it: a steady speech-like rise and fall.
func unmeasuredSpeechLevel(at time: TimeInterval) -> Double {
    0.55 + 0.25 * sin(time * 9) * sin(time * 2.3)
}

final class VoiceMeter {
    let layer = CALayer()
    private var bars: [CALayer] = []
    private let userFile: URL
    private let botFile: URL
    private var track: LevelTrack?
    private var trackModified: Date?
    private var level = 0.0
    private var shownSource = MeterSource.none

    // photoRect is the photo's place in the layer the meter is added to.
    init(folder: URL, photoRect: CGRect) {
        userFile = folder.appendingPathComponent("level-user.txt")
        botFile = folder.appendingPathComponent("level-bot.txt")
        layer.frame = photoRect
        layer.opacity = 0
        let rowWidth = CGFloat(meterBarCount) * meterBarWidth + CGFloat(meterBarCount - 1) * meterBarGap
        let left = (photoRect.width - rowWidth) / 2
        for index in 0..<meterBarCount {
            let bar = CALayer()
            bar.frame = CGRect(x: left + CGFloat(index) * (meterBarWidth + meterBarGap), y: meterBottomInset,
                               width: meterBarWidth, height: meterMinBarHeight)
            bar.cornerRadius = meterBarWidth / 2
            bar.backgroundColor = MeterColors.bot.cgColor
            bar.shadowColor = MeterColors.shadow.cgColor
            bar.shadowOpacity = 0.35
            bar.shadowRadius = 2
            bar.shadowOffset = CGSize(width: 0, height: -1)
            layer.addSublayer(bar)
            bars.append(bar)
        }
    }

    func update(source: MeterSource) {
        let now = Date().timeIntervalSince1970
        level = smoothedLevel(previous: level, target: targetLevel(source: source, at: now))
        if source != shownSource { show(source) }
        guard source != .none || layer.opacity > 0 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (bar, height) in zip(bars, barHeights(level: level, at: now)) {
            bar.frame.size.height = height
        }
        CATransaction.commit()
    }

    private func show(_ source: MeterSource) {
        shownSource = source
        CATransaction.begin()
        CATransaction.setAnimationDuration(meterFadeSeconds)
        layer.opacity = source == .none ? 0 : 1
        if source != .none {
            let color = (source == .user ? MeterColors.user : MeterColors.bot).cgColor
            bars.forEach { $0.backgroundColor = color }
        }
        CATransaction.commit()
    }

    private func targetLevel(source: MeterSource, at now: TimeInterval) -> Double {
        switch source {
        case .none: return 0
        case .user: return userLevel(at: now)
        case .bot: return botLevel(at: now)
        }
    }

    private func modified(_ file: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date
    }

    private func userLevel(at now: TimeInterval) -> Double {
        guard let changed = modified(userFile), now - changed.timeIntervalSince1970 < userLevelFreshSeconds,
              let text = try? String(contentsOf: userFile, encoding: .utf8) else { return 0 }
        return Double(text.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    private func botLevel(at now: TimeInterval) -> Double {
        guard let changed = modified(botFile) else {
            track = nil
            trackModified = nil
            return unmeasuredSpeechLevel(at: now)
        }
        if changed != trackModified, let text = try? String(contentsOf: botFile, encoding: .utf8) {
            track = LevelTrack.parse(text)
            trackModified = changed
        }
        return track?.level(at: now) ?? unmeasuredSpeechLevel(at: now)
    }
}

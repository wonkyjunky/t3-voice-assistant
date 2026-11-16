// Everything heard in one listening turn, and which language to believe.
//
// The on-device Korean recognizer starts over after each pause: it sends one result with word
// timing that closes the stretch just spoken, then partial results with only the new words.
// Without keeping the closed stretches, everything said before the last pause was lost (seen with
// --audio-file: 25 s of speech with pauses came out as its last 13 characters). Partial results
// never carry timing or confidence; closing and final results carry both.
//
// The primary language (Korean or English, chosen in the avatar's menu) listens live. Only one
// on-device recognizer runs at a time (seen with --audio-file: of two started together, only one
// ever got results), so when the primary one is unsure, the other language listens to the recorded
// audio afterwards and the surer one wins. Measured with --audio-file: the recognizer for the
// language spoken scored 0.61 to 0.99, the other one 0.01 to 0.17.

// The other language must beat the primary one by this much, so the primary wins near ties.
let secondaryMargin: Float = 0.1
// A one-word result in the other language beats the primary one only when the primary scored
// below this: English heard the Korean "아니" as "Annie" at 0.85, while Korean scored it 0.60.
let singleWordPrimaryFloor: Float = 0.5
// The primary language at or above this is sent at once, with no check and no delay. Short English
// can still score fairly high in Korean ("okay send it" came out as "오케이" at 0.53), so the bar is
// well above that; a check of a few seconds of audio took about 0.2 s.
let secondCheckBelow: Float = 0.7

struct Stretch: Equatable {
    let text: String
    let confidence: Float?
}

struct Transcript: Equatable {
    private(set) var closed: [Stretch] = []
    private(set) var open = ""

    var text: String {
        (closed.map(\.text) + [open]).filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// The closed stretches' confidence, weighted by their length; nil when none has one yet.
    var confidence: Float? {
        let scored = closed.compactMap { stretch in stretch.confidence.map { (Float(max(stretch.text.count, 1)), $0) } }
        guard !scored.isEmpty else { return nil }
        let weight = scored.map(\.0).reduce(0, +)
        return scored.map { $0.0 * $0.1 }.reduce(0, +) / weight
    }

    func adding(_ words: String, closesStretch: Bool, confidence: Float? = nil) -> Transcript {
        var next = self
        guard closesStretch else {
            next.open = words
            return next
        }
        guard !words.isEmpty else { return self }
        let stretch = Stretch(text: words, confidence: confidence)
        // A close with no new words since the last one repeats or corrects that same stretch.
        if open.isEmpty, !closed.isEmpty {
            next.closed[next.closed.count - 1] = stretch
        } else {
            next.closed.append(stretch)
        }
        next.open = ""
        return next
    }
}

/// The transcript to send: the other language only when it was clearly surer than the primary one.
func chosenTranscript(primary: Transcript, secondary: Transcript?) -> (usedSecondary: Bool, transcript: Transcript) {
    guard let secondary, !secondary.text.isEmpty else { return (false, primary) }
    if primary.text.isEmpty { return (true, secondary) }
    let primaryScore = primary.confidence ?? 0
    guard let secondaryScore = secondary.confidence else { return (false, primary) }
    let singleWord = secondary.text.split(separator: " ").count < 2
    if singleWord && primaryScore >= singleWordPrimaryFloor { return (false, primary) }
    return secondaryScore > primaryScore + secondaryMargin ? (true, secondary) : (false, primary)
}

/// Whether the recorded audio should be heard again in the other language: the primary one was
/// unsure, unscored, or heard no words although there was sound.
func needsSecondCheck(primary: Transcript, heardSound: Bool) -> Bool {
    guard heardSound else { return false }
    guard !primary.text.isEmpty, let score = primary.confidence else { return true }
    return score < secondCheckBelow
}

// Whether sound is speech, judged against the microphone's own background, which differs a lot
// between microphones (AirPods room noise under 0.035 with speech at 0.2 to 0.45; a Jabra headset's
// speech about 0.05; an Elgato dock's silence about 0.0015). The background is a low percentile of
// the recent buffer peaks, so the short gaps between words keep it at the room's level while talking.
let backgroundWindow = 240
let backgroundPercentile = 0.1
let speechOverBackground: Float = 4
let quietestSpeech: Float = 0.004

struct LoudnessTracker {
    private var recent: [Float] = []

    mutating func isSpeech(peak: Float) -> Bool {
        let threshold = max(backgroundLevel * speechOverBackground, quietestSpeech)
        recent.append(peak)
        if recent.count > backgroundWindow { recent.removeFirst() }
        return peak > threshold
    }

    private var backgroundLevel: Float {
        guard !recent.isEmpty else { return 0 }
        let sorted = recent.sorted()
        return sorted[Int(Double(sorted.count - 1) * backgroundPercentile)]
    }
}

/// The language that listens live, from the setting the avatar's menu writes: "ko" or "en".
func primaryLanguage(setting: String?) -> String {
    setting?.trimmingCharacters(in: .whitespacesAndNewlines) == "en" ? "en" : "ko"
}

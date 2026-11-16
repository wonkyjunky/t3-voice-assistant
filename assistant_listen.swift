// assistant_listen: listen to the microphone once, without any window, and print what was said.
//
// Uses the built-in macOS speech recognizers for Korean and English, on this Mac only (no audio leaves it).
// Listening ends when the speaker pauses after talking, or when nobody speaks at all.
// Prints the recognized text on standard output (empty when nothing was heard).
// Nothing heard or said is written anywhere else.
//
// Exit status: 0 done (text may be empty), 1 failed, 2 permission denied, 3 recognizer or
// microphone unavailable.
//
// Usage: assistant_listen                 listen once
//        assistant_listen --say <text>    open the microphone, say <text>, then listen
//        assistant_listen --sound <file>  open the microphone, play <file>, then listen
//        assistant_listen --check         report permissions and availability without listening
//
// The cue plays only after the microphone is fully open (a Bluetooth headset can take a second
// or two to switch), and sound during the cue is thrown away, so the speaker can talk the
// moment the cue ends.
//
// Standard error carries only status lines (why listening ended, how many characters, and a
// final "status=N"), never the words.
//
// Build with build_listen.sh. It wraps the program in AssistantListen.app, because macOS checks
// the speech permission text of the app that launched a process: started from a shortcut's
// shell, that is the shortcut runner, which has no such text, and macOS kills the process.
// Launched with `open`, the app is responsible for itself and asks for permission by its name.

import AVFoundation
import Foundation
import Speech

// The primary language (set in the avatar's menu, saved in primary-language next to the app)
// listens live; when it is unsure, the other one listens to the recorded audio and the surer one
// wins (listen_transcript.swift).
let localeIdentifiers = ["ko": "ko-KR", "en": "en-US"]
// Built from the bundle here: appFolder is declared further down and not yet set at this point.
let primaryLanguageURL = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("primary-language")
// After the user stops, how long to wait for the primary recognizer's final result and its confidence.
let finalResultWaitSeconds: TimeInterval = 1.5
// How long the other language's check of the recording may take.
let secondCheckWaitSeconds: TimeInterval = 4
let tickSeconds: TimeInterval = 0.2
let maxListenSeconds: TimeInterval = 60
let noSpeechErrorCode = 1110
let cueVoice = "Yuna"
// Opening the microphone switches a Bluetooth headset into call mode, which swallows the start
// of any sound played meanwhile. Wait for the first audio from the microphone, then a little more.
let firstAudioTimeoutSeconds: TimeInterval = 2.0
let routeSettleSeconds: TimeInterval = 0.3
// Listening opens this long before a cue sound ends.
let cueOverlapSeconds: TimeInterval = 0.15
// Kept alive while the cue plays (it would stop if released).
var cuePlayer: AVAudioPlayer?

// For the avatar next to this app: the words heard so far (its caption bubble) and how loud the
// voice is (its sound bars), as one number from 0 to 1 about 25 times a second. Only the user can
// read either file; talk.sh removes them when the conversation ends.
let appFolder = Bundle.main.bundleURL.deletingLastPathComponent()
let captionURL = appFolder.appendingPathComponent("caption-user.txt")
let levelURL = appFolder.appendingPathComponent("level-user.txt")
let levelWriteSeconds: TimeInterval = 0.04
// Loudness below full scale: quietDecibels and softer is no bar, loudDecibels and louder full bars.
let quietDecibels: Float = -50
let loudDecibels: Float = -10

// Written next to the file and renamed into place, so the avatar never reads half of it.
func writePrivate(_ text: String, to url: URL) {
    let temporary = url.path + ".tmp"
    guard FileManager.default.createFile(atPath: temporary, contents: Data(text.utf8),
                                         attributes: [.posixPermissions: 0o600]) else { return }
    rename(temporary, url.path)
}

// Test only: `--audio-file <path>` listens to an audio file instead of the microphone, at the pace
// it would be spoken and with silence after it, and logs every partial result with its words and
// timing. Use it only with made-up test speech.
let testAudioPath: String? = {
    let arguments = CommandLine.arguments
    guard let flag = arguments.firstIndex(of: "--audio-file"), flag + 1 < arguments.count else { return nil }
    return arguments[flag + 1]
}()
let testChunkSeconds = 0.1
func meterLevel(rms: Float) -> Float {
    guard rms > 0 else { return 0 }
    let decibels = 20 * log10(rms)
    return min(1, max(0, (decibels - quietDecibels) / (loudDecibels - quietDecibels)))
}
let pollSeconds: TimeInterval = 0.05

// Words the recognizer should expect, so the assistant's name is not heard as a similar word.
// install.sh puts the assistant's name (and how it is called, such as 하나야) in vocabulary.txt.
// More words, one per line, can go in vocabulary.txt next to the app (lines starting with # are skipped).
let baseVocabulary: [String] = []
let maxVocabularyWords = 100

/// The names of the assistant in use (persona.py: "persona" names it; another assistant's
/// assistant-name.txt is in personas/<id>/), so an assistant picked in the avatar's menu is heard.
func personaWords(folder: URL) -> [String] {
    let chosen = ((try? String(contentsOf: folder.appendingPathComponent("persona"), encoding: .utf8)) ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !chosen.isEmpty, chosen != "main", !chosen.contains("/") else { return [] }
    let names = folder.appendingPathComponent("personas/\(chosen)/assistant-name.txt")
    return ((try? String(contentsOf: names, encoding: .utf8)) ?? "")
        .split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
}

func loadVocabulary() -> [String] {
    let folder = Bundle.main.bundleURL.deletingLastPathComponent()
    let url = folder.appendingPathComponent("vocabulary.txt")
    let lines = ((try? String(contentsOf: url, encoding: .utf8)) ?? "").split(whereSeparator: \.isNewline)
    let extra = lines
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    var seen = Set<String>()
    let words = (personaWords(folder: folder) + baseVocabulary + extra).filter { seen.insert($0).inserted }
    return Array(words.prefix(maxVocabularyWords))
}

enum Cue {
    case speech(String)
    case sound(String)
}

func cueFromArguments() -> Cue? {
    let arguments = CommandLine.arguments
    func value(after flag: String) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }
    if let text = value(after: "--say") { return .speech(text) }
    if let path = value(after: "--sound") { return .sound(path) }
    return nil
}

// Plays the cue and returns shortly before it ends, so listening starts as the cue finishes.
// Sounds play inside this app (no player process to start); speech still uses `say`.
func play(_ cue: Cue) {
    switch cue {
    case .sound(let path):
        guard let player = try? AVAudioPlayer(contentsOf: URL(fileURLWithPath: path)) else {
            writeError("cue failed: cannot open the sound")
            return
        }
        cuePlayer = player
        player.prepareToPlay()
        player.play()
        Thread.sleep(forTimeInterval: max(player.duration - cueOverlapSeconds, 0))
    case .speech(let text):
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        process.arguments = ["-v", cueVoice, text]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            writeError("cue failed: \(error.localizedDescription)")
        }
    }
}

enum ExitStatus: Int32 {
    case ok = 0, failed = 1, denied = 2, unavailable = 3
}

func seconds(fromEnvironment name: String, default fallback: TimeInterval) -> TimeInterval {
    guard let raw = ProcessInfo.processInfo.environment[name], let value = Double(raw), value > 0 else {
        return fallback
    }
    return value
}

// Time allowed before the first word, and the pause that ends a sentence.
let startTimeoutSeconds = seconds(fromEnvironment: "LISTEN_START_TIMEOUT", default: 8)
let silenceSeconds = seconds(fromEnvironment: "LISTEN_SILENCE_SECONDS", default: 1.8)
// A short start such as "음" is usually someone still thinking, so wait longer then.
let shortUtteranceCharacters = 5
let shortUtterancePauseSeconds: TimeInterval = 2.5
// Whether a buffer is the speaker still talking is judged against the microphone's own background
// (LoudnessTracker in listen_transcript.swift): a fixed level missed soft speech on quieter headsets.

let processStartedAt = Date()

// Every status line carries the time since start, so slow steps show up in voice.log.
func writeError(_ message: String) {
    let elapsedMs = Int(Date().timeIntervalSince(processStartedAt) * 1000)
    FileHandle.standardError.write(Data("assistant_listen: +\(elapsedMs)ms \(message)\n".utf8))
}

func quit(_ status: ExitStatus, error message: String? = nil) -> Never {
    if let message { writeError(message) }
    writeError("status=\(status.rawValue)")
    exit(status.rawValue)
}

// Asking again when permission is already given costs over two seconds, so check first.
func requestSpeechPermission() -> SFSpeechRecognizerAuthorizationStatus {
    if SFSpeechRecognizer.authorizationStatus() == .authorized { return .authorized }
    let done = DispatchSemaphore(value: 0)
    var status = SFSpeechRecognizerAuthorizationStatus.notDetermined
    SFSpeechRecognizer.requestAuthorization { granted in
        status = granted
        done.signal()
    }
    done.wait()
    return status
}

func requestMicrophonePermission() -> Bool {
    if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized { return true }
    let done = DispatchSemaphore(value: 0)
    var allowed = false
    AVCaptureDevice.requestAccess(for: .audio) { granted in
        allowed = granted
        done.signal()
    }
    done.wait()
    return allowed
}

/// An on-device recognizer for the language, or nil when this Mac cannot recognize it on device now.
func makeRecognizer(_ identifier: String) -> SFSpeechRecognizer? {
    guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: identifier)),
          recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else { return nil }
    return recognizer
}

func reportStatus() -> Never {
    let speech = SFSpeechRecognizer.authorizationStatus().rawValue
    let microphone = AVCaptureDevice.authorizationStatus(for: .audio).rawValue
    print("speech permission: \(speech) (0 not asked, 1 denied, 2 restricted, 3 allowed)")
    print("microphone permission: \(microphone) (0 not asked, 1 restricted, 2 denied, 3 allowed)")
    for identifier in localeIdentifiers.values.sorted() {
        print("\(identifier) on-device recognizer ready: \(makeRecognizer(identifier) != nil)")
    }
    quit(.ok)
}

// Lets audio through to the recognizer only once opened (after the cue), and counts buffers and
// keeps the loudest sample, to tell "no sound arrived" apart from "sound arrived but nothing was
// recognized". Only numbers, never the audio itself.
final class AudioMeter {
    private let lock = NSLock()
    private var isOpen = false
    private var hasAudio = false
    private var bufferCount = 0
    private var peakLevel: Float = 0
    private var lastLoudAt: Date?
    private var lastLevelAt = Date.distantPast
    private var loudness = LoudnessTracker()

    /// When the speaker was last heard clearly above the microphone's background (nil before that).
    var lastLoudTime: Date? {
        lock.lock()
        defer { lock.unlock() }
        return lastLoudAt
    }

    var audioHasArrived: Bool {
        lock.lock()
        defer { lock.unlock() }
        return hasAudio
    }

    func open() {
        lock.lock()
        isOpen = true
        lock.unlock()
    }

    func close() {
        lock.lock()
        isOpen = false
        lock.unlock()
    }

    /// Records the buffer and tells whether it should go to the recognizer. While open, it also
    /// passes the loudness on to the avatar's sound bars every levelWriteSeconds.
    func admit(_ buffer: AVAudioPCMBuffer) -> Bool {
        var loudest: Float = 0
        var squares: Float = 0
        let count = Int(buffer.frameLength)
        if let samples = buffer.floatChannelData?[0] {
            for index in 0..<count {
                loudest = max(loudest, abs(samples[index]))
                squares += samples[index] * samples[index]
            }
        }
        guard let publishLevel = record(loudest: loudest) else { return false }
        if publishLevel {
            let rms = count > 0 ? (squares / Float(count)).squareRoot() : 0
            writePrivate(String(format: "%.3f", meterLevel(rms: rms)), to: levelURL)
        }
        return true
    }

    /// nil while closed; otherwise whether the loudness is due to be passed on.
    private func record(loudest: Float) -> Bool? {
        lock.lock()
        defer { lock.unlock() }
        hasAudio = true
        guard isOpen else { return nil }
        bufferCount += 1
        peakLevel = max(peakLevel, loudest)
        let now = Date()
        if loudness.isSpeech(peak: loudest) { lastLoudAt = now }
        guard now.timeIntervalSince(lastLevelAt) >= levelWriteSeconds else { return false }
        lastLevelAt = now
        return true
    }

    var summary: String {
        lock.lock()
        defer { lock.unlock() }
        return "buffers=\(bufferCount) peak=\(String(format: "%.4f", peakLevel))"
    }
}

// voice.py names its player in speaking.pid while the assistant's voice plays.
func isAssistantSpeaking() -> Bool {
    let url = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("speaking.pid")
    guard let raw = try? String(contentsOf: url, encoding: .utf8),
          let pid = pid_t(raw.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
    return kill(pid, 0) == 0
}

// Played when listening resumes after the assistant spoke (the first one that exists).
// sounds/cue.caf next to the app is the same cue talk.sh uses; replacing that file
// changes both without rebuilding.
let resumeCuePaths = [
    Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("sounds/cue.caf").path,
    "/System/Library/PrivateFrameworks/AssistantServices.framework/Versions/A/Resources/siri-begin-improved.caf",
    "/System/Library/Sounds/Tink.aiff",
]

final class Listener {
    private let meter = AudioMeter()
    private let recording = AudioRecording()
    private var inputDescription = ""
    private let engine = AVAudioEngine()
    private let primary: RecognitionChannel
    private let secondaryRecognizer: SFSpeechRecognizer?
    private let secondaryLanguage: String
    private let vocabulary: [String]
    private var secondary: RecognitionChannel?
    private let cue: Cue?
    private var startedAt = Date()
    private var lastChangeAt = Date()
    private var latestText = ""
    private var finishing = false
    private var finishReason = ""
    private var completed = false
    private var pausedForSpeech = false
    private var resuming = false

    init(cue: Cue?, primary: RecognitionChannel, secondaryLanguage: String, secondaryRecognizer: SFSpeechRecognizer?,
         vocabulary: [String]) {
        self.cue = cue
        self.primary = primary
        self.secondaryLanguage = secondaryLanguage
        self.secondaryRecognizer = secondaryRecognizer
        self.vocabulary = vocabulary
    }

    func start() {
        if let testAudioPath {
            startTestAudio(path: testAudioPath)
            return
        }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            quit(.unavailable, error: "no microphone input")
        }
        let deviceName = AVCaptureDevice.default(for: .audio)?.localizedName ?? "unknown"
        inputDescription = "input=\(deviceName) \(Int(format.sampleRate))Hz \(format.channelCount)ch"
        let primary = self.primary
        let recording = self.recording
        let meter = self.meter
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            guard meter.admit(buffer) else { return }
            primary.append(buffer)
            recording.add(buffer)
        }
        writeError("step: starting microphone")
        engine.prepare()
        do {
            try engine.start()
        } catch {
            quit(.failed, error: "cannot start the microphone: \(error.localizedDescription)")
        }

        guard let cue else {
            beginRecognition()
            return
        }
        DispatchQueue.global().async { [weak self] in
            let waitStarted = Date()
            while !meter.audioHasArrived && Date().timeIntervalSince(waitStarted) < firstAudioTimeoutSeconds {
                Thread.sleep(forTimeInterval: pollSeconds)
            }
            let waitedMs = Int(Date().timeIntervalSince(waitStarted) * 1000)
            writeError("microphone audio after \(waitedMs)ms, arrived=\(meter.audioHasArrived)")
            Thread.sleep(forTimeInterval: routeSettleSeconds)
            self?.markState(from: ["waking"], to: "greeting")
            writeError("step: cue starts")
            play(cue)
            writeError("step: cue ended")
            DispatchQueue.main.async { self?.beginRecognition() }
        }
    }

    private func startTestAudio(path: String) {
        guard let file = try? AVAudioFile(forReading: URL(fileURLWithPath: path)) else {
            quit(.failed, error: "cannot open the test audio file")
        }
        inputDescription = "input=test file"
        beginRecognition()
        let primary = self.primary
        let recording = self.recording
        let meter = self.meter
        let format = file.processingFormat
        let frames = AVAudioFrameCount(format.sampleRate * testChunkSeconds)
        DispatchQueue.global().async {
            while true {
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return }
                if (try? file.read(into: buffer, frameCount: frames)) == nil || buffer.frameLength == 0 {
                    buffer.frameLength = frames
                    for channel in 0..<Int(format.channelCount) {
                        buffer.floatChannelData?[channel].update(repeating: 0, count: Int(frames))
                    }
                }
                if meter.admit(buffer) {
                    primary.append(buffer)
                    recording.add(buffer)
                }
                Thread.sleep(forTimeInterval: testChunkSeconds)
            }
        }
    }

    private func beginRecognition() {
        markListening()
        startedAt = Date()
        lastChangeAt = startedAt
        meter.open()
        primary.start { [weak self] _ in self?.primaryUpdated() }
        Timer.scheduledTimer(withTimeInterval: tickSeconds, repeats: true) { [weak self] _ in
            self?.checkTime()
        }
    }

    private func primaryUpdated() {
        guard !completed else { return }
        let text = primary.transcript.text
        if text != latestText {
            latestText = text
            lastChangeAt = Date()
            if !text.isEmpty { writePrivate(text, to: captionURL) }
        }
        guard primary.done else { return }
        if finishing {
            decide()
            return
        }
        if text.isEmpty, let failure = primary.failure, secondaryRecognizer == nil {
            stopMicrophone()
            quit(.failed, error: "recognition failed: \(failure.domain) \(failure.code) \(failure.localizedDescription)")
        }
        finish(reason: text.isEmpty ? "recognizer heard no speech" : "recognizer finished")
    }

    private func checkTime() {
        guard !finishing else { return }
        if waitsForAssistant() { return }
        let now = Date()
        // Speech the live recognizer cannot write down (Korean while English listens) still counts,
        // so listening waits for the pause and the other language then checks the recording.
        let heardSomething = !latestText.isEmpty || meter.lastLoudTime != nil
        if !heardSomething && now.timeIntervalSince(startedAt) > startTimeoutSeconds {
            finish(reason: "no words within \(startTimeoutSeconds)s")
        }
        if heardSomething {
            // Still talking while either new words or loud sound keep coming.
            let lastActivity = max(lastChangeAt, meter.lastLoudTime ?? lastChangeAt)
            let pauseLimit = latestText.count <= shortUtteranceCharacters ? shortUtterancePauseSeconds : silenceSeconds
            if now.timeIntervalSince(lastActivity) > pauseLimit {
                finish(reason: "pause after speech (\(pauseLimit)s)")
            }
        }
        if now.timeIntervalSince(startedAt) > maxListenSeconds {
            finish(reason: "longest listening time reached")
        }
    }

    /// A reply from another thread can make the assistant speak while this listens. Then the timers
    /// wait and its voice is kept out of the recognizer; afterwards the cue plays and listening
    /// starts over. Returns true while waiting.
    private func waitsForAssistant() -> Bool {
        if resuming { return true }
        if isAssistantSpeaking() {
            if !pausedForSpeech {
                pausedForSpeech = true
                meter.close()
                writeError("step: paused while the assistant speaks")
            }
            return true
        }
        guard pausedForSpeech else { return false }
        pausedForSpeech = false
        resuming = true
        DispatchQueue.global().async { [weak self] in
            if let path = resumeCuePaths.first(where: { FileManager.default.fileExists(atPath: $0) }) {
                play(.sound(path))
            }
            DispatchQueue.main.async { self?.resumeListening() }
        }
        return true
    }

    private func resumeListening() {
        resuming = false
        startedAt = Date()
        lastChangeAt = startedAt
        meter.open()
        writeError("step: listening again")
    }

    /// talk.sh sets talk.state to "greeting" while the greeting plays; once listening
    /// starts, the avatar should show it, so the state becomes "listening" right now.
    private func markListening() {
        markState(from: ["waking", "greeting"], to: "listening")
    }

    /// Moves talk.state on only from the given states, so it never overrides the talk script.
    func markState(from expected: Set<String>, to next: String) {
        let url = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("talk.state")
        guard let raw = try? String(contentsOf: url, encoding: .utf8),
              expected.contains(raw.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
        try? "\(next)\n".write(to: url, atomically: true, encoding: .utf8)
    }

    private func stopMicrophone() {
        meter.close()
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        try? FileManager.default.removeItem(at: levelURL)
    }

    /// Stops listening and lets the primary recognizer finish, so its final result carries a confidence.
    private func finish(reason: String) {
        guard !finishing else { return }
        finishing = true
        finishReason = reason
        writeError("step: stopping microphone")
        stopMicrophone()
        primary.endAudio()
        if primary.done {
            decide()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + finalResultWaitSeconds) { [weak self] in
            self?.decide()
        }
    }

    /// Sends the primary language when it was sure; otherwise the other one first listens to the recording.
    private func decide() {
        guard !completed, secondary == nil else { return }
        primary.cancel()
        guard needsSecondCheck(primary: primary.transcript, heardSound: meter.lastLoudTime != nil),
              let secondaryRecognizer else {
            send(secondary: nil)
            return
        }
        writeError("step: \(primary.language) unsure, \(secondaryLanguage) listens to the recording")
        let channel = RecognitionChannel(language: secondaryLanguage, recognizer: secondaryRecognizer, vocabulary: vocabulary)
        secondary = channel
        channel.start { [weak self] channel in
            if channel.done { self?.send(secondary: channel) }
        }
        recording.all().forEach { channel.append($0) }
        channel.endAudio()
        DispatchQueue.main.asyncAfter(deadline: .now() + secondCheckWaitSeconds) { [weak self] in
            self?.send(secondary: channel)
        }
    }

    /// Sends what the surer recognizer heard. The log keeps only the language and the scores.
    private func send(secondary: RecognitionChannel?) {
        guard !completed else { return }
        completed = true
        secondary?.cancel()
        let choice = chosenTranscript(primary: primary.transcript, secondary: secondary?.transcript)
        let language = choice.usedSecondary ? secondaryLanguage : primary.language
        let text = choice.transcript.text
        if !text.isEmpty { writePrivate(text, to: captionURL) }
        let score: (RecognitionChannel?) -> String = { channel in
            guard let channel else { return "not asked" }
            return channel.transcript.confidence.map { String(format: "%.2f", $0) } ?? "-"
        }
        let results = primary.results + (secondary?.results ?? 0)
        writeError("ended: \(finishReason), language=\(language) confidence \(primary.language)=\(score(primary)) \(secondaryLanguage)=\(score(secondary)), characters=\(text.count) results=\(results) \(meter.summary) \(inputDescription)")
        FileHandle.standardOutput.write(Data((text + "\n").utf8))
        quit(.ok)
    }
}

if CommandLine.arguments.contains("--check") { reportStatus() }

writeError("step: started")
let speechStatus = requestSpeechPermission()
writeError("step: speech permission checked")
guard speechStatus == .authorized else {
    quit(.denied, error: "speech recognition permission not granted (status \(speechStatus.rawValue))")
}
guard requestMicrophonePermission() else { quit(.denied, error: "microphone permission not granted") }

writeError("step: permissions ok")
let primaryCode = primaryLanguage(setting: try? String(contentsOf: primaryLanguageURL, encoding: .utf8))
let secondaryCode = primaryCode == "ko" ? "en" : "ko"
guard let primaryRecognizer = makeRecognizer(localeIdentifiers[primaryCode] ?? "ko-KR") else {
    quit(.unavailable, error: "on-device recognition for \(primaryCode) is not available now")
}
let vocabulary = loadVocabulary()
writeError("vocabulary words=\(vocabulary.count), primary language \(primaryCode)")
let secondaryRecognizer = makeRecognizer(localeIdentifiers[secondaryCode] ?? "en-US")
if secondaryRecognizer == nil { writeError("\(secondaryCode) recognition is not available, listening in \(primaryCode) only") }
let listener = Listener(
    cue: cueFromArguments(),
    primary: RecognitionChannel(language: primaryCode, recognizer: primaryRecognizer, vocabulary: vocabulary),
    secondaryLanguage: secondaryCode,
    secondaryRecognizer: secondaryRecognizer,
    vocabulary: vocabulary
)
listener.start()
RunLoop.main.run()

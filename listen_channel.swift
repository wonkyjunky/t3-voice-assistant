// One on-device recognizer listening in one language, and what it has heard so far; and the
// recording of a turn's audio.
//
// Korean listens live. Only one on-device recognizer runs at a time, so when Korean is unsure,
// English listens to the recording afterwards and the surer one is sent (listen_transcript.swift).

import Speech

/// A copy of the buffer: the audio engine reuses its buffers, so a recording must keep its own.
func copied(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
    guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength),
          let source = buffer.floatChannelData, let target = copy.floatChannelData else { return nil }
    copy.frameLength = buffer.frameLength
    for channel in 0..<Int(buffer.format.channelCount) {
        target[channel].update(from: source[channel], count: Int(buffer.frameLength))
    }
    return copy
}

/// The turn's microphone audio, kept in memory only (never written to disk) for the English check.
final class AudioRecording {
    private let lock = NSLock()
    private var buffers: [AVAudioPCMBuffer] = []

    func add(_ buffer: AVAudioPCMBuffer) {
        guard let copy = copied(buffer) else { return }
        lock.lock()
        buffers.append(copy)
        lock.unlock()
    }

    func all() -> [AVAudioPCMBuffer] {
        lock.lock()
        defer { lock.unlock() }
        return buffers
    }
}

final class RecognitionChannel {
    let language: String
    private let recognizer: SFSpeechRecognizer
    private let request = SFSpeechAudioBufferRecognitionRequest()
    private var task: SFSpeechRecognitionTask?
    private(set) var transcript = Transcript()
    private(set) var results = 0
    // A final result, "no speech", or a failure: nothing more will come.
    private(set) var done = false
    private(set) var failure: NSError?

    init(language: String, recognizer: SFSpeechRecognizer, vocabulary: [String]) {
        self.language = language
        self.recognizer = recognizer
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.contextualStrings = vocabulary
    }

    func start(onUpdate: @escaping (RecognitionChannel) -> Void) {
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.take(result: result, error: error)
                onUpdate(self)
            }
        }
    }

    /// Called from the audio thread for every microphone buffer, or with the recorded audio.
    func append(_ buffer: AVAudioPCMBuffer) {
        request.append(buffer)
    }

    /// No more audio; the recognizer then sends its final result (with confidence) and is done.
    func endAudio() {
        request.endAudio()
    }

    func cancel() {
        task?.cancel()
    }

    private func take(result: SFSpeechRecognitionResult?, error: Error?) {
        guard !done else { return }
        if let result {
            results += 1
            let segments = result.bestTranscription.segments
            let words = result.bestTranscription.formattedString
            // Only a result that closes a stretch of speech, or the final one, carries timing and confidence.
            let closes = result.isFinal || segments.contains { $0.timestamp + $0.duration > 0 }
            let confidence = segments.isEmpty ? nil : segments.map(\.confidence).reduce(0, +) / Float(segments.count)
            transcript = transcript.adding(words, closesStretch: closes, confidence: closes ? confidence : nil)
            if testAudioPath != nil {
                let score = closes ? String(format: "%.2f", confidence ?? 0) : "-"
                writeError("partial \(language): closes=\(closes) final=\(result.isFinal) conf=\(score) text=\(words)")
            }
            if result.isFinal { done = true }
            return
        }
        guard let error else { return }
        done = true
        let nsError = error as NSError
        if nsError.code != noSpeechErrorCode { failure = nsError }
    }
}

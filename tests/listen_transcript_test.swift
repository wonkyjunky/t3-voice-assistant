// Checks how the listener keeps everything said across pauses. Run: tests/run_listen_logic_test.sh

import Foundation

var failures = 0

func expect(_ condition: Bool, _ name: String) {
    if condition {
        print("ok    \(name)")
    } else {
        failures += 1
        print("FAIL  \(name)")
    }
}

// The order of results the on-device recognizer really sent for speech with pauses (logged with
// --audio-file): partial results without timing, then one result with timing that closes the
// stretch, after which it starts over with only the new words.
do {
    var transcript = Transcript()
    transcript = transcript.adding("민준님 부", closesStretch: false)
    transcript = transcript.adding("민준님 부르셨어요", closesStretch: false)
    expect(transcript.text == "민준님 부르셨어요", "partial results replace each other")

    transcript = transcript.adding("민준님 부르셨어요", closesStretch: true)
    transcript = transcript.adding("알", closesStretch: false)
    expect(transcript.text == "민준님 부르셨어요 알", "words after a pause are added, not swapped in")

    transcript = transcript.adding("알겠어요", closesStretch: false)
    transcript = transcript.adding("알겠어요 또 불러 주세요", closesStretch: true)
    transcript = transcript.adding("미안", closesStretch: false)
    expect(transcript.text == "민준님 부르셨어요 알겠어요 또 불러 주세요 미안", "every stretch is kept")
}

do {
    let closed = Transcript().adding("블루 스트", closesStretch: false).adding("블로그 스레드", closesStretch: true)
    expect(closed.text == "블로그 스레드", "the closing result's corrected words win over the partial ones")
    let twice = closed.adding("블로그 스레드", closesStretch: true)
    expect(twice.text == "블로그 스레드", "the same stretch closed twice is kept once")
    let revised = closed.adding("블로그 스레드야", closesStretch: true)
    expect(revised.text == "블로그 스레드야", "a stretch closed again with corrections replaces itself")
}

do {
    expect(Transcript().text.isEmpty, "nothing heard is empty")
    let empty = Transcript().adding("", closesStretch: true).adding("네", closesStretch: false)
    expect(empty.text == "네", "an empty closing result adds nothing")
}

// Confidence, measured with --audio-file: the right recognizer scored 0.61 to 0.99, the wrong one
// 0.01 to 0.17. Partial results carry none; closing and final results do.
do {
    let korean = Transcript().adding("민준님 부르셨어요", closesStretch: true, confidence: 0.9)
        .adding("알", closesStretch: false)
        .adding("알겠어 또 불러", closesStretch: true, confidence: 0.7)
    expect(abs((korean.confidence ?? 0) - 0.8) < 0.05, "confidence is the average over closed stretches")
    expect(Transcript().adding("부분", closesStretch: false).confidence == nil, "partial results give no confidence")
    let corrected = Transcript().adding("블로그", closesStretch: true, confidence: 0.2).adding("블로그야", closesStretch: true, confidence: 0.9)
    expect(corrected.confidence == 0.9, "a corrected stretch replaces its confidence too")
}

do {
    let koreanSpeechKo = Transcript().adding("미안 듣기를 시작 못했어", closesStretch: true, confidence: 0.9)
    let koreanSpeechEn = Transcript().adding("I guess Opa Tola", closesStretch: true, confidence: 0.07)
    expect(!chosenTranscript(primary: koreanSpeechKo, secondary: koreanSpeechEn).usedSecondary, "Korean speech picks Korean")

    let englishSpeechKo = Transcript().adding("Can you check with the back read it", closesStretch: true, confidence: 0.17)
    let englishSpeechEn = Transcript().adding("Can you check what the blog thread is doing", closesStretch: true, confidence: 0.92)
    let english = chosenTranscript(primary: englishSpeechKo, secondary: englishSpeechEn)
    expect(english.usedSecondary && english.transcript.text.hasPrefix("Can you check what"), "English speech picks English")

    let close = chosenTranscript(primary: Transcript().adding("네", closesStretch: true, confidence: 0.8),
                                 secondary: Transcript().adding("Nay", closesStretch: true, confidence: 0.85))
    expect(!close.usedSecondary, "a near tie stays Korean")
    let noEnglish = chosenTranscript(primary: koreanSpeechKo, secondary: nil)
    expect(!noEnglish.usedSecondary, "without an English recognizer it is Korean")
    let emptyEnglish = chosenTranscript(primary: koreanSpeechKo, secondary: Transcript())
    expect(!emptyEnglish.usedSecondary, "an English recognizer that heard nothing is ignored")
    let onlyEnglish = chosenTranscript(primary: Transcript(), secondary: englishSpeechEn)
    expect(onlyEnglish.usedSecondary, "only English heard is English")
    // Measured: English heard the Korean "아니" as "Annie" at 0.85; Korean scored it 0.60.
    let annie = chosenTranscript(primary: Transcript().adding("아니", closesStretch: true, confidence: 0.60),
                                 secondary: Transcript().adding("Annie", closesStretch: true, confidence: 0.85))
    expect(!annie.usedSecondary, "a single English word does not beat a fair Korean score")
    let okay = chosenTranscript(primary: Transcript().adding("오케이", closesStretch: true, confidence: 0.53),
                                secondary: Transcript().adding("OK send it", closesStretch: true, confidence: 0.96))
    expect(okay.usedSecondary, "a short English sentence beats a Korean loanword")
    let lostWord = chosenTranscript(primary: Transcript().adding("스", closesStretch: true, confidence: 0.3),
                                    secondary: Transcript().adding("Stop", closesStretch: true, confidence: 0.9))
    expect(lostWord.usedSecondary, "a single English word wins when Korean is lost")
    let unscored = chosenTranscript(primary: Transcript().adding("안녕", closesStretch: false),
                                    secondary: Transcript().adding("Annyeong", closesStretch: false))
    expect(!unscored.usedSecondary, "with no confidence at all it is Korean")
}

// Only one on-device recognizer runs at a time, so English listens to the recorded audio again
// only when Korean was unsure or heard nothing.
do {
    let sure = Transcript().adding("미안 듣기를 시작 못했어", closesStretch: true, confidence: 0.78)
    expect(!needsSecondCheck(primary: sure, heardSound: true), "sure Korean is sent at once")
    let lost = Transcript().adding("Can you check with the back", closesStretch: true, confidence: 0.17)
    expect(needsSecondCheck(primary: lost, heardSound: true), "unsure Korean asks English")
    expect(needsSecondCheck(primary: Transcript(), heardSound: true), "sound without Korean words asks English")
    expect(!needsSecondCheck(primary: Transcript(), heardSound: false), "silence asks no one")
    let unscored = Transcript().adding("블로그 스레드", closesStretch: false)
    expect(needsSecondCheck(primary: unscored, heardSound: true), "Korean without a score asks English")
}

// English as the primary language (set in the avatar's menu): English listens live, Korean checks.
do {
    let englishSure = Transcript().adding("Play some music", closesStretch: true, confidence: 0.96)
    expect(!needsSecondCheck(primary: englishSure, heardSound: true), "sure English is sent at once when English is primary")
    let koreanSpeech = chosenTranscript(primary: Transcript().adding("I guess Opa Tola", closesStretch: true, confidence: 0.07),
                                        secondary: Transcript().adding("미안 듣기를 시작 못했어", closesStretch: true, confidence: 0.9))
    expect(koreanSpeech.usedSecondary, "Korean speech still wins when English is primary")
    expect(primaryLanguage(setting: "en\n") == "en", "the setting can make English primary")
    expect(primaryLanguage(setting: "ko") == "ko" && primaryLanguage(setting: nil) == "ko" && primaryLanguage(setting: "fr") == "ko",
           "Korean is primary by default and for anything else")
}

// Whether a buffer is speech, judged against the microphone's own background level. Measured
// peaks: AirPods room noise under 0.035 and speech 0.2 to 0.45; a Jabra headset's speech only
// about 0.05; an Elgato dock's silence about 0.0015.
do {
    var quiet = LoudnessTracker()
    for _ in 0..<60 { _ = quiet.isSpeech(peak: 0.003) }
    expect(quiet.isSpeech(peak: 0.04), "soft speech on a quiet microphone counts as speech")
    expect(!quiet.isSpeech(peak: 0.004), "its background does not")

    var airpods = LoudnessTracker()
    for _ in 0..<60 { _ = airpods.isSpeech(peak: 0.03) }
    expect(!airpods.isSpeech(peak: 0.035), "room noise on a louder microphone is not speech")
    expect(airpods.isSpeech(peak: 0.25), "speech on it is")

    var silent = LoudnessTracker()
    for _ in 0..<60 { _ = silent.isSpeech(peak: 0) }
    expect(!silent.isSpeech(peak: 0.002), "a tiny blip after digital silence is not speech")

    var talking = LoudnessTracker()
    for _ in 0..<60 { _ = talking.isSpeech(peak: 0.003) }
    for index in 0..<150 { _ = talking.isSpeech(peak: index % 4 == 0 ? 0.004 : 0.05) }
    expect(talking.isSpeech(peak: 0.05), "long speech with short gaps still counts as speech")
}

print(failures == 0 ? "all passed" : "\(failures) failed")
exit(failures == 0 ? 0 : 1)

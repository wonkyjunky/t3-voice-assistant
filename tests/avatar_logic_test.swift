// Checks the avatar's caption and sound-bar logic without starting the app.
// Run: tests/run_avatar_logic_test.sh

import AppKit

var failures = 0

func expect(_ condition: Bool, _ name: String) {
    if condition {
        print("ok    \(name)")
    } else {
        failures += 1
        print("FAIL  \(name)")
    }
}

// Captions: the user's words, then the reply that fills in while it is spoken, then both fade.
do {
    var board = CaptionBoard.empty.heardUser("블로그 스레드 뭐 해?", at: 0)
    board = board.ticked(speaking: false, at: 1)
    expect(board.user?.text == "블로그 스레드 뭐 해?" && board.bot == nil, "the user's words show alone while the assistant thinks")
    expect(board.opacity(at: 1) == 1, "the user's words are fully visible")

    board = board.heardBot("테스트 돌리는 중이야.", at: 2).ticked(speaking: false, at: 2)
    expect(board.user != nil, "the reply keeps the words it answers")
    expect(board.botShown(at: 2) == nil, "the reply waits for the voice")

    board = board.ticked(speaking: true, at: 3)
    expect(board.botShown(at: 3) == "테", "the reply starts with the first character")
    expect(board.botShown(at: 4)?.count == 8, "the reply fills in at the pace of speech")

    board = board.ticked(speaking: false, at: 4)
    expect(board.botShown(at: 4) == "테스트 돌리는 중이야.", "the whole reply shows once the voice stops")
    expect(board.opacity(at: 8) == 1, "the bubbles stay a few seconds after the voice stops")
    expect(abs(board.opacity(at: 9.3) - 0.5) < 0.01, "then they fade")
    expect(board.ticked(speaking: false, at: 10).isEmpty, "and are gone")
}

// English goes by about twice as many characters a second as Korean (one Hangul syllable is a
// spoken beat; English letters, spaces and marks are lighter), so it keeps up with the voice.
do {
    let english = CaptionBoard.empty.heardBot("The blog thread is running its tests right now.", at: 0)
        .ticked(speaking: true, at: 1)
    let shown = english.botShown(at: 2)?.count ?? 0
    expect(shown >= 13 && shown <= 17, "an English reply fills in at the pace of English speech (\(shown) chars after 1 s)")
    let korean = CaptionBoard.empty.heardBot("블로그 스레드는 지금 테스트를 돌리는 중이에요.", at: 0)
        .ticked(speaking: true, at: 1)
    let koreanShown = korean.botShown(at: 2)?.count ?? 0
    expect(koreanShown >= 7 && koreanShown <= 9, "a Korean reply keeps its pace (\(koreanShown) chars after 1 s)")
}

do {
    let replied = CaptionBoard.empty.heardUser("음악 틀어줘", at: 0).heardBot("틀었어!", at: 1)
    let report = replied.heardBot("배포 끝났대!", at: 20)
    expect(report.user == nil && report.bot?.text == "배포 끝났대!", "a second reply in a row stands alone")
    let next = replied.heardUser("고마워", at: 21)
    expect(next.bot == nil && next.user?.text == "고마워", "new words from the user start a new exchange")
}

do {
    let silent = CaptionBoard.empty.heardBot("말 없는 대답", at: 0).ticked(speaking: false, at: 5)
    expect(silent.botShown(at: 5) != nil, "a reply whose voice never starts still shows")
    let waiting = CaptionBoard.empty.heardUser("여보세요", at: 0)
    expect(waiting.ticked(speaking: false, at: 89).user != nil, "unanswered words wait for a reply")
    expect(waiting.ticked(speaking: false, at: 91).isEmpty, "but not forever")
}

// Long text is never cut: the bubble grows to its largest size and the rest scrolls inside it.
do {
    let long = Array(repeating: "아주 긴 대답이 계속 이어지고 있어요.", count: 20).joined(separator: " ") + " 끝"
    let bubble = CaptionBubble(fromUser: false)
    let size = bubble.show(long)
    expect(bubble.shownText == long, "a long caption keeps all of its words, with no ellipsis")
    expect(size.height <= CaptionBubble.maxHeight(fromUser: false) + 0.5, "a long caption stays within the largest bubble")
    expect(bubble.isScrolled, "a long caption scrolls to its newest line")
    let short = CaptionBubble(fromUser: false)
    let shortSize = short.show("짧은 말")
    expect(shortSize.height < CaptionBubble.maxHeight(fromUser: false) && !short.isScrolled, "a short caption fits without scrolling")
}

// The pointer over a bubble keeps it on screen, and the bubble can be scrolled back by hand.
do {
    let ended = CaptionBoard.empty.heardBot("다 됐어", at: 0).ticked(speaking: true, at: 1).ticked(speaking: false, at: 4)
    expect(ended.fadeStart == 4 + captionLingerSeconds, "without the pointer the bubble fades as usual")
    let held = ended.holding(at: 8.9)
    expect(held.fadeStart == 8.9 + captionHoverGraceSeconds, "with the pointer on it the fade waits")
    expect(!held.ticked(speaking: false, at: 9.7).isEmpty, "so it is still there while being read")

    let long = Array(repeating: "아주 긴 대답이 계속 이어지고 있어요.", count: 20).joined(separator: " ")
    let bubble = CaptionBubble(fromUser: false)
    _ = bubble.show(long, follow: true)
    expect(bubble.scrollOffset == 0 && bubble.maxScrollOffset > 0, "a long reply starts at its newest line")
    bubble.scroll(by: 30)
    expect(bubble.scrollOffset == 30, "scrolling up shows earlier lines")
    bubble.scroll(by: 100_000)
    expect(bubble.scrollOffset == bubble.maxScrollOffset, "scrolling stops at the first line")
    bubble.scroll(by: -100_000)
    expect(bubble.scrollOffset == 0, "and at the newest line")
    bubble.scroll(by: 30)
    _ = bubble.show(long + " 그리고 새 문장이 한 줄 더 이어지고 또 이어져요.", follow: false)
    expect(bubble.scrollOffset > 30, "new words while the pointer is on it keep the same lines in view")
    _ = bubble.show(long + " 그리고 새 문장이 한 줄 더 이어지고 또 이어져요.", follow: true)
    expect(bubble.scrollOffset == 0, "when the pointer leaves it goes back to the newest line")
}

// A slow voice (seen: the ElevenLabs stream timed out after 16 s, then a retry played) must not
// use up the reply's bubble before the voice starts.
do {
    var slow = CaptionBoard.empty.heardUser("응 보내", at: 0).heardBot("보냈어!", at: 1)
    slow = slow.ticked(speaking: false, voicePending: true, at: 10)
    expect(slow.botShown(at: 10) == nil && slow.user != nil, "while the voice is still being made the reply waits, with the words it answers")
    slow = slow.ticked(speaking: false, voicePending: true, at: 22)
    expect(!slow.isEmpty && slow.fadeStart == nil, "and nothing fades, however long it takes")
    slow = slow.ticked(speaking: true, voicePending: true, at: 23)
    expect(slow.botShown(at: 23) == "보", "then it fills in with the voice")
    let voiceless = CaptionBoard.empty.heardBot("소리 없이", at: 0).ticked(speaking: false, voicePending: false, at: 5)
    expect(voiceless.botShown(at: 5) != nil, "a reply with no voice coming still shows after a few seconds")
}

// Ending the conversation clears a bubble that was waiting for a reply.
do {
    let waiting = CaptionBoard.empty.heardUser("OK", at: 0).ticked(speaking: false, conversationOpen: true, at: 5)
    expect(waiting.fadeStart == captionUnansweredSeconds, "while the conversation is open the words wait for a reply")
    let closed = waiting.ticked(speaking: false, conversationOpen: false, at: 10)
    expect(closed.fadeStart == 10 + captionClosedLingerSeconds, "once it ends they fade soon")
    expect(closed.ticked(speaking: false, conversationOpen: false, at: 10 + captionClosedLingerSeconds + captionFadeSeconds).isEmpty,
           "and are gone")
}

// Sound bars.
do {
    let track = LevelTrack.parse("start 100.000 step 0.05 pid 42\n0.2\n0.9\n0.4\n")
    expect(track?.values == [0.2, 0.9, 0.4], "the reply's loudness track is read")
    expect(track?.level(at: 100.0) == 0, "quiet before the player makes sound")
    expect(track?.level(at: 100.0 + playerStartSeconds + 0.06) == 0.9, "the level follows the time since playback started")
    expect(track?.level(at: 200) == 0, "quiet after the last number")
    expect(LevelTrack.parse("nonsense") == nil, "a broken track is ignored")
    expect(LevelTrack.parse("start 1.0 step 0.05 pid 1\n")?.values == [], "a track with no numbers yet is empty")
}

do {
    expect(smoothedLevel(previous: 0.2, target: 0.8) == 0.8, "bars rise at once")
    let falling = smoothedLevel(previous: 0.8, target: 0)
    expect(falling > 0.6 && falling < 0.8, "bars fall smoothly")
    let quiet = barHeights(level: 0, at: 3)
    let loud = barHeights(level: 1, at: 3)
    expect(quiet.count == meterBarCount && quiet.allSatisfy { $0 == meterMinBarHeight }, "silence shows short bars")
    expect(loud.allSatisfy { $0 > meterMinBarHeight && $0 <= meterMaxBarHeight }, "a loud voice shows tall bars within bounds")
    expect(loud[3] > loud[0], "the middle bar is the tallest")
}

print(failures == 0 ? "all passed" : "\(failures) failed")
exit(failures == 0 ? 0 : 1)

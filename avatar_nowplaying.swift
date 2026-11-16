// What plays now, for the "now playing" card next to the avatar (avatar_nowplaying_card.swift):
// YouTube or YouTube Music in Google Chrome, or the Music app. Each answer says whether it plays or is paused, and which
// buttons the card offers for it.
//
// Every few seconds a separate process asks a player that is already running (it never starts
// Chrome or Music): Chrome runs one line of JavaScript in each YouTube
// tab (this needs "Allow JavaScript from Apple Events" and, once, the Automation permission for
// this app), and Music reports its current track. Its own process keeps a slow answer from
// holding up the avatar.

import AppKit

enum NowPlayingSource: Equatable {
    case youtube, music
}

struct NowPlaying: Equatable {
    let title: String
    let detail: String
    let source: NowPlayingSource
    let isPlaying: Bool
    /// The music's own volume, 0-100 (not the Mac's), when the source tells it.
    let volume: Int?

    init(title: String, detail: String, source: NowPlayingSource, isPlaying: Bool, volume: Int? = nil) {
        self.title = title
        self.detail = detail
        self.source = source
        self.isPlaying = isPlaying
        self.volume = volume.map { min(max($0, 0), 100) }
    }

    func with(isPlaying: Bool) -> NowPlaying {
        NowPlaying(title: title, detail: detail, source: source, isPlaying: isPlaying, volume: volume)
    }

    func with(volume: Int) -> NowPlaying {
        NowPlaying(title: title, detail: detail, source: source, isPlaying: isPlaying, volume: volume)
    }
}

/// The mac_control.py command that sets a source's own volume.
func macControlVolumeArguments(_ level: Int, on playing: NowPlaying) -> [String] {
    [playing.source == .music ? "music" : "youtube", "volume", String(min(max(level, 0), 100))]
}

enum NowPlayingControl: Equatable {
    case previous, playPause, next
}

let nowPlayingCheckSeconds: TimeInterval = 3
let nowPlayingScriptTimeout: TimeInterval = 2.5
let nowPlayingShownDefaultsKey = "nowPlayingShown"
// A paused song keeps its card this long, so it can be played again from the card.
let pausedCardSeconds: TimeInterval = 120
let chromeBundleID = "com.google.Chrome"
let musicBundleID = "com.apple.Music"
let youtubeTitleSuffixes = [" - YouTube Music", " - YouTube"]

func nowPlayingShown() -> Bool {
    UserDefaults.standard.object(forKey: nowPlayingShownDefaultsKey) as? Bool ?? true
}

/// The buttons the card shows for a source, left to right.
func controls(for source: NowPlayingSource) -> [NowPlayingControl] {
    switch source {
    case .youtube: return [.playPause, .next]
    case .music: return [.previous, .playPause, .next]
    }
}

/// The mac_control.py command a button runs.
func macControlArguments(for control: NowPlayingControl, on playing: NowPlaying) -> [String] {
    if playing.source == .music {
        switch control {
        case .previous: return ["music", "previous"]
        case .next: return ["music", "next"]
        // play (not toggle), so mac_control.py pauses music playing elsewhere first.
        case .playPause: return ["music", playing.isPlaying ? "pause" : "play"]
        }
    }
    switch control {
    case .playPause: return ["youtube", playing.isPlaying ? "pause" : "resume"]
    case .next, .previous: return ["youtube", "next"]
    }
}

/// Whether the card shows: always while playing, and for pausedCardSeconds after the song was
/// last seen playing.
func cardShows(_ playing: NowPlaying?, lastPlayingAt: Date?, now: Date) -> Bool {
    guard let playing else { return false }
    if playing.isPlaying { return true }
    guard let lastPlayingAt else { return false }
    return now.timeIntervalSince(lastPlayingAt) <= pausedCardSeconds
}

/// The Chrome script's answer, "<tab URL>\n<JSON from the page>", for the playing YouTube tab (or
/// a paused one that had started).
func parseChromeNowPlaying(_ output: String) -> NowPlaying? {
    let parts = output.split(separator: "\n", maxSplits: 1).map(String.init)
    guard parts.count == 2, let data = parts[1].data(using: .utf8),
          let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
    let playing = json["playing"] as? Bool == true
    guard playing || json["started"] as? Bool == true else { return nil }
    var title = (json["title"] as? String ?? "").trimmingCharacters(in: .whitespaces)
    for suffix in youtubeTitleSuffixes where title.hasSuffix(suffix) {
        title = String(title.dropLast(suffix.count))
    }
    guard !title.isEmpty else { return nil }
    let artist = (json["artist"] as? String ?? "").trimmingCharacters(in: .whitespaces)
    let place = parts[0].contains("music.youtube.com") ? "YouTube Music" : "YouTube"
    let detail = artist.isEmpty ? place : "\(artist) · \(place)"
    let volume = (json["volume"] as? NSNumber)?.intValue
    return NowPlaying(title: title, detail: detail, source: .youtube, isPlaying: playing, volume: volume)
}

/// The Music script's answer: "<playing|paused>\n<track>\n<artist>\n<volume>", or nothing when stopped.
func parseMusicNowPlaying(_ output: String) -> NowPlaying? {
    let lines = output.split(separator: "\n", omittingEmptySubsequences: false).map {
        $0.trimmingCharacters(in: .whitespaces)
    }
    guard lines.count >= 2, ["playing", "paused"].contains(lines[0]), !lines[1].isEmpty else { return nil }
    let artist = lines.count > 2 ? lines[2] : ""
    let volume = lines.count > 3 ? Int(lines[3]) : nil
    return NowPlaying(title: lines[1], detail: artist.isEmpty ? "Music" : "\(artist) · Music", source: .music,
                      isPlaying: lines[0] == "playing", volume: volume)
}

// The playing tab wins; otherwise the first paused tab whose video had started.
private let pageJavaScript = "(function(){var v=document.querySelector('video');if(!v)return '';"
    + "var m=navigator.mediaSession&&navigator.mediaSession.metadata;"
    + "return JSON.stringify({playing:!v.paused&&!v.ended,started:v.currentTime>0&&!v.ended,"
    + "volume:Math.round(v.volume*100),title:(m&&m.title)||document.title,artist:(m&&m.artist)||''});})()"

// Each script asks "is it running?" itself, right before talking to the player: a script sent
// to an app that just quit would launch it again, and the card must never open Chrome or Music.
private let chromeScript = #"""
if application id "\#(chromeBundleID)" is not running then return ""
set pausedTab to ""
tell application id "\#(chromeBundleID)"
    repeat with aWindow in windows
        repeat with aTab in tabs of aWindow
            set tabURL to URL of aTab
            if tabURL contains "youtube.com" then
                set answer to execute aTab javascript "\#(pageJavaScript)"
                if answer is not missing value then
                    if answer contains "\"playing\":true" then return tabURL & linefeed & answer
                    if pausedTab is "" and answer contains "\"started\":true" then set pausedTab to tabURL & linefeed & answer
                end if
            end if
        end repeat
    end repeat
end tell
return pausedTab
"""#

private let musicScript = """
if application id "\(musicBundleID)" is not running then return ""
tell application id "\(musicBundleID)"
    set currentState to player state
    if currentState is playing or currentState is paused then return (currentState as text) & linefeed & (name of current track) & linefeed & (artist of current track) & linefeed & (sound volume as text)
end tell
return ""
"""

private func isRunning(_ bundleID: String) -> Bool {
    NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).contains { !$0.isTerminated }
}

/// The process's output, or nil when it cannot start or takes too long.
private func output(of executable: String, _ arguments: [String]) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let outputPipe = Pipe()
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = outputPipe
    process.standardError = FileHandle.nullDevice
    do {
        try process.run()
    } catch {
        return nil
    }
    let deadline = Date().addingTimeInterval(nowPlayingScriptTimeout)
    while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
    if process.isRunning {
        process.terminate()
        return nil
    }
    let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Which of the places with music the card shows: one that plays (in the order found), else the
/// place it showed before, else the first paused one.
func pickNowPlaying(_ found: [NowPlaying], shownBefore: NowPlayingSource?) -> NowPlaying? {
    found.first { $0.isPlaying } ?? found.first { $0.source == shownBefore } ?? found.first
}

/// Every place with music now: a YouTube tab in Chrome, the Music app.
func everythingPlaying(folder: URL) -> [NowPlaying] {
    var found: [NowPlaying] = []
    if isRunning(chromeBundleID), let answer = output(of: "/usr/bin/osascript", ["-e", chromeScript]),
       let playing = parseChromeNowPlaying(answer) {
        found.append(playing)
    }
    if isRunning(musicBundleID), let answer = output(of: "/usr/bin/osascript", ["-e", musicScript]),
       let playing = parseMusicNowPlaying(answer) {
        found.append(playing)
    }
    return found
}

// The avatar's menu, shown from an icon in the menu bar and on a right-click on the photo: the
// current state, starting or ending a conversation, what is shown (the avatar, captions, sound
// bars), the avatar's size and place, the ElevenLabs characters left, and quitting.
//
// The menu bar icon follows the state, so it says what is going on even when the avatar is hidden.

import AppKit

let avatarShownDefaultsKey = "avatarShown"
let meterShownDefaultsKey = "meterShown"
// The words of the menu, the hover label and the usage line: English unless Korean is chosen in the menu.
let menuLanguageDefaultsKey = "menuLanguage"

func menuLanguage() -> String {
    UserDefaults.standard.string(forKey: menuLanguageDefaultsKey) == "ko" ? "ko" : "en"
}

func ui(_ english: String, _ korean: String) -> String {
    menuLanguage() == "ko" ? korean : english
}

let avatarSizes: [(english: String, korean: String, scale: CGFloat)] = [
    ("Small", "작게", 0.75), ("Medium", "보통", 1), ("Large", "크게", 1.4),
]
// Asking ElevenLabs runs a small Python check that can take seconds; its answer is reused this long.
let creditRefreshSeconds: TimeInterval = 60
var creditPending: String { ui("ElevenLabs: checking characters left…", "ElevenLabs 남은 글자 확인 중…") }
var idleTitle: String { ui("\(assistantEnglishName) · idle", "\(assistantName) · 대기 중") }

// The language the listener hears first (the other one is checked when it is unsure) and the voice
// falls back to. AssistantListen.app and voice.py read this file next to the app on every turn.
let primaryLanguageFile = files.base.appendingPathComponent("primary-language")
let languageChoices: [(code: String, english: String, korean: String)] = [("ko", "Korean", "한국어"), ("en", "English", "English")]
let menuLanguageChoices: [(code: String, title: String)] = [("en", "English"), ("ko", "한국어")]

func savedPrimaryLanguage() -> String {
    let saved = (try? String(contentsOf: primaryLanguageFile, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
    return saved == "en" ? "en" : "ko"
}

func shownSetting(_ key: String) -> Bool {
    UserDefaults.standard.object(forKey: key) as? Bool ?? true
}

func avatarShown() -> Bool { shownSetting(avatarShownDefaultsKey) }
func meterShown() -> Bool { shownSetting(meterShownDefaultsKey) }

func conversationRunning() -> Bool {
    let lock = files.base.appendingPathComponent("talk.lock/pid")
    guard let raw = try? String(contentsOf: lock, encoding: .utf8),
          let pid = pid_t(raw.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
    return kill(pid, 0) == 0
}

// Where the window goes so that the photo, at this scale, sits screenMargin from the top right
// corner of the visible screen, just under the menu bar (the transparent effect space may hang
// over the edge). This is the avatar's first place, and where "Move to top right" puts it back.
func cornerOrigin(scale: CGFloat, in visible: NSRect) -> NSPoint {
    let reach = (avatarSide + effectPadding) * scale
    return NSPoint(x: visible.maxX - screenMargin - reach, y: visible.maxY - screenMargin - reach)
}

func menuBarSymbol(for state: AvatarState) -> String {
    switch state {
    case .idle: return "waveform.circle"
    case .waking, .greeting: return "hand.wave"
    case .listening: return "mic.fill"
    case .replying: return "ellipsis.bubble"
    case .speaking: return "waveform"
    }
}

final class AvatarMenu: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let avatarView: AvatarView
    private let panel: NSPanel
    private let hotkey: Hotkey
    private var state = AvatarState.idle
    private var shownSymbol = ""
    private var credit = creditPending
    private var creditCheckedAt = Date.distantPast

    init(avatarView: AvatarView, panel: NSPanel, hotkey: Hotkey) {
        self.avatarView = avatarView
        self.panel = panel
        self.hotkey = hotkey
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        show(.idle)
    }

    private var headerTitle: String { state == .idle ? idleTitle : state.label }

    // Called on every avatar tick; the icon only changes when the state does.
    func show(_ newState: AvatarState) {
        state = newState
        let symbol = menuBarSymbol(for: newState)
        guard symbol != shownSymbol else { return }
        shownSymbol = symbol
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: headerTitle)
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = headerTitle
    }

    func popUp(with event: NSEvent, for view: NSView) {
        let menu = NSMenu()
        fill(menu)
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        fill(menu)
    }

    private func fill(_ menu: NSMenu) {
        menu.removeAllItems()
        let header = NSMenuItem(title: headerTitle, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())
        let talk = conversationRunning() ? ui("End conversation", "대화 끝내기") : ui("Start conversation", "대화 시작")
        add(talk, #selector(toggleTalk), to: menu)
        let personas = personaList(base: files.base)
        if personas.count > 1 { menu.addItem(personaMenuItem(personas)) }
        menu.addItem(hotkeyMenuItem())
        menu.addItem(languageMenuItem())
        menu.addItem(menuLanguageMenuItem())
        menu.addItem(.separator())
        add(ui("Show avatar", "아바타 보이기"), #selector(toggleAvatar), checked: avatarShown(), to: menu)
        add(ui("Show captions", "자막 보이기"), #selector(toggleCaptions), checked: captionsShown(), to: menu)
        add(ui("Show sound bars", "소리 막대 보이기"), #selector(toggleMeter), checked: meterShown(), to: menu)
        add(ui("Show now playing", "재생 중 보이기"), #selector(toggleNowPlaying), checked: nowPlayingShown(), to: menu)
        if detachedNowPlayingFrame() != nil {
            add(ui("Attach now playing to avatar", "재생 카드 아바타 옆으로"), #selector(attachNowPlaying), to: menu)
        }
        menu.addItem(sizeMenuItem())
        add(ui("Move to top right", "오른쪽 위로 옮기기"), #selector(resetPosition), to: menu)
        menu.addItem(.separator())
        let creditItem = NSMenuItem(title: credit, action: nil, keyEquivalent: "")
        creditItem.isEnabled = false
        menu.addItem(creditItem)
        refreshCredit(into: creditItem)
        menu.addItem(.separator())
        add(ui("Quit avatar", "아바타 종료"), #selector(quit), to: menu)
    }

    private func hotkeyMenuItem() -> NSMenuItem {
        let keys = NSMenu()
        for (index, choice) in hotkeyChoices.enumerated() {
            let note = choice.switchesInputSource ? ui(" (also switches input source)", " (한/영 전환과 겹침)") : ""
            add(choice.title + note, #selector(chooseHotkey(_:)), checked: hotkey.index == index, to: keys).tag = index
        }
        keys.addItem(.separator())
        add(ui("Off", "끄기"), #selector(chooseHotkey(_:)), checked: hotkey.index == hotkeyOff, to: keys).tag = hotkeyOff
        let state = hotkey.index == hotkeyOff || hotkey.registered ? hotkey.title : "\(hotkey.title), \(ui("not registered", "등록 안 됨"))"
        let item = NSMenuItem(title: "\(ui("Shortcut", "단축키")): \(state)", action: nil, keyEquivalent: "")
        item.submenu = keys
        return item
    }

    // "Assistant: 하나" with every assistant to switch to (docs/PERSONAS.md). Each talks in its own thread.
    private func personaMenuItem(_ personas: [Persona]) -> NSMenuItem {
        let choices = NSMenu()
        for (index, persona) in personas.enumerated() {
            add(ui(persona.nameEnglish, persona.nameKorean), #selector(choosePersona(_:)),
                checked: persona.id == activePersona.id, to: choices).tag = index
        }
        let item = NSMenuItem(title: "\(ui("Assistant", "비서")): \(ui(assistantEnglishName, assistantName))",
                              action: nil, keyEquivalent: "")
        item.submenu = choices
        return item
    }

    private func languageMenuItem() -> NSMenuItem {
        let languages = NSMenu()
        let current = savedPrimaryLanguage()
        for (index, choice) in languageChoices.enumerated() {
            add(ui(choice.english, choice.korean), #selector(chooseLanguage(_:)), checked: choice.code == current, to: languages).tag = index
        }
        let name = languageChoices.first { $0.code == current }.map { ui($0.english, $0.korean) } ?? ""
        let item = NSMenuItem(title: "\(ui("Main spoken language", "기본 언어")): \(name)", action: nil, keyEquivalent: "")
        item.submenu = languages
        return item
    }

    private func menuLanguageMenuItem() -> NSMenuItem {
        let languages = NSMenu()
        let current = menuLanguage()
        for (index, choice) in menuLanguageChoices.enumerated() {
            add(choice.title, #selector(chooseMenuLanguage(_:)), checked: choice.code == current, to: languages).tag = index
        }
        let item = NSMenuItem(title: ui("Menu language: English", "메뉴 언어: 한국어"), action: nil, keyEquivalent: "")
        item.submenu = languages
        return item
    }

    private func sizeMenuItem() -> NSMenuItem {
        let sizes = NSMenu()
        let current = currentScale()
        for (index, size) in avatarSizes.enumerated() {
            let item = add(ui(size.english, size.korean), #selector(chooseSize(_:)), checked: abs(current - size.scale) < 0.01, to: sizes)
            item.tag = index
        }
        let item = NSMenuItem(title: ui("Avatar size", "아바타 크기"), action: nil, keyEquivalent: "")
        item.submenu = sizes
        return item
    }

    @discardableResult
    private func add(_ title: String, _ action: Selector, checked: Bool? = nil, to menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        if let checked { item.state = checked ? .on : .off }
        menu.addItem(item)
        return item
    }

    // Runs in the background and fills in the menu while it is open, so opening it never waits.
    private func refreshCredit(into item: NSMenuItem) {
        guard Date().timeIntervalSince(creditCheckedAt) > creditRefreshSeconds else { return }
        creditCheckedAt = Date()
        DispatchQueue.global().async { [weak self, weak item] in
            let summary = "ElevenLabs \(creditSummary())"
            DispatchQueue.main.async {
                self?.credit = summary
                item?.title = summary
            }
        }
    }

    private func currentScale() -> CGFloat {
        let saved = UserDefaults.standard.double(forKey: scaleDefaultsKey)
        return saved > 0 ? CGFloat(saved) : 1
    }

    @objc private func toggleTalk() { toggleConversation() }

    @objc private func chooseHotkey(_ sender: NSMenuItem) { hotkey.choose(sender.tag) }

    // The usage line is asked for again in the new language; the hover label changes at once.
    @objc private func chooseMenuLanguage(_ sender: NSMenuItem) {
        guard menuLanguageChoices.indices.contains(sender.tag) else { return }
        UserDefaults.standard.set(menuLanguageChoices[sender.tag].code, forKey: menuLanguageDefaultsKey)
        credit = creditPending
        creditCheckedAt = .distantPast
        shownSymbol = ""
        show(state)
        avatarView.refreshLabel()
    }

    @objc private func choosePersona(_ sender: NSMenuItem) {
        let all = personaList(base: files.base)
        guard all.indices.contains(sender.tag), all[sender.tag] != activePersona else { return }
        savePersonaChoice(all[sender.tag].id, base: files.base)
        activePersona = all[sender.tag]
        avatarView.reloadPersona()
    }

    @objc private func chooseLanguage(_ sender: NSMenuItem) {
        guard languageChoices.indices.contains(sender.tag) else { return }
        do {
            try "\(languageChoices[sender.tag].code)\n".write(to: primaryLanguageFile, atomically: true, encoding: .utf8)
        } catch {
            NSLog("assistant_avatar: cannot save the primary language: \(error.localizedDescription)")
        }
    }

    @objc private func toggleAvatar() {
        let shown = !avatarShown()
        UserDefaults.standard.set(shown, forKey: avatarShownDefaultsKey)
        if shown { panel.orderFrontRegardless() } else { panel.orderOut(nil) }
    }

    @objc private func toggleCaptions() { UserDefaults.standard.set(!captionsShown(), forKey: captionsShownDefaultsKey) }

    @objc private func toggleMeter() { UserDefaults.standard.set(!meterShown(), forKey: meterShownDefaultsKey) }

    @objc private func toggleNowPlaying() { UserDefaults.standard.set(!nowPlayingShown(), forKey: nowPlayingShownDefaultsKey) }

    @objc private func attachNowPlaying() { attachNowPlayingToAvatar() }

    @objc private func chooseSize(_ sender: NSMenuItem) {
        avatarView.applyScale(avatarSizes[sender.tag].scale, save: true)
    }

    // Back to the first place, the top right corner, at the current size: the photo keeps the
    // usual margin from the screen's edges whether it is small or large. Saved like a drag, as the
    // base-size origin around the same centre, so it is there again after a restart.
    // Puts everything back in its first place: the avatar in the top right corner, and the
    // now-playing card back beside it if it was set apart.
    @objc private func resetPosition() {
        attachNowPlayingToAvatar()
        guard let screen = panel.screen ?? NSScreen.main else { return }
        let side = panel.frame.width
        let origin = cornerOrigin(scale: side / panelSide, in: screen.visibleFrame)
        panel.setFrameOrigin(origin)
        savePosition(NSPoint(x: origin.x + (side - panelSide) / 2, y: origin.y + (side - panelSide) / 2))
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

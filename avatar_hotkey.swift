// A key combination that starts a conversation, cuts the assistant off or ends the conversation from any
// app, handled by the avatar app itself (no Shortcuts app in between), the same as a click on the
// avatar. It uses the system's hot key registration, which needs no extra permission. The key is
// chosen (or turned off) in the menu, which also says when the system refuses it. The system does
// not stop two apps from taking the same key (checked on macOS 27), and a system shortcut on the
// same key wins, so the choices avoid keys macOS and common apps use.

import Carbon

struct HotkeyChoice {
    let title: String
    let keyCode: UInt32
    let modifiers: UInt32
    // macOS uses this key to switch input sources (한/영) by default; the menu says so.
    let switchesInputSource: Bool
}

// The first is the default. ⌃⌥Space is macOS's "next input source" (한/영) key, on by default,
// and ⌥Space is used by apps such as Claude's quick entry, so neither is the default.
let hotkeyChoices: [HotkeyChoice] = [
    HotkeyChoice(title: "⌃⌥C", keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(controlKey | optionKey), switchesInputSource: false),
    HotkeyChoice(title: "⌃⌥⌘Space", keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey | cmdKey),
                 switchesInputSource: false),
    HotkeyChoice(title: "⌥Space", keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey), switchesInputSource: false),
    HotkeyChoice(title: "⌃⌥Space", keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey), switchesInputSource: true),
]
let hotkeyDefaultsKey = "hotkeyChoice"
let hotkeyOff = -1
let hotkeySignature: OSType = 0x5641_5354  // "VAST"
// A second press this soon after the first is ignored, so one press never toggles twice.
let hotkeyRepeatSeconds: TimeInterval = 0.4

func savedHotkeyIndex() -> Int {
    let saved = UserDefaults.standard.object(forKey: hotkeyDefaultsKey) as? Int ?? 0
    return saved == hotkeyOff || hotkeyChoices.indices.contains(saved) ? saved : 0
}

// Registers one choice for this app. Returns the system's status (noErr when it worked).
func registerHotkey(_ choice: HotkeyChoice, into ref: inout EventHotKeyRef?) -> OSStatus {
    let id = EventHotKeyID(signature: hotkeySignature, id: 1)
    return RegisterEventHotKey(choice.keyCode, choice.modifiers, id, GetApplicationEventTarget(), 0, &ref)
}

final class Hotkey {
    private let action: () -> Void
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var lastPress = Date.distantPast
    private(set) var index = hotkeyOff
    private(set) var registered = false

    init(action: @escaping () -> Void) {
        self.action = action
        installHandler()
        choose(savedHotkeyIndex())
    }

    var title: String {
        index == hotkeyOff ? ui("off", "끔") : hotkeyChoices[index].title
    }

    func choose(_ newIndex: Int) {
        if let ref {
            UnregisterEventHotKey(ref)
            self.ref = nil
        }
        index = newIndex
        UserDefaults.standard.set(newIndex, forKey: hotkeyDefaultsKey)
        guard newIndex != hotkeyOff else {
            registered = false
            return
        }
        registered = registerHotkey(hotkeyChoices[newIndex], into: &ref) == noErr
        if !registered {
            NSLog("assistant_avatar: the system refused the hot key \(hotkeyChoices[newIndex].title)")
        }
    }

    fileprivate func pressed() {
        guard Date().timeIntervalSince(lastPress) > hotkeyRepeatSeconds else { return }
        lastPress = Date()
        action()
    }

    private func installHandler() {
        var pressedEvent = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            Unmanaged<Hotkey>.fromOpaque(userData).takeUnretainedValue().pressed()
            return noErr
        }, 1, &pressedEvent, me, &handler)
    }
}

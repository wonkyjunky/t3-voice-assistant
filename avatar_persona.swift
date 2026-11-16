// Which assistant the avatar is, picked in the menu ("Assistant") when there is more than one.
// persona.py holds the same rules for the scripts: the main assistant ("main") has its files next
// to the app; more assistants live in personas/<id>/ (each with a persona.conf, see
// docs/PERSONAS.md) with their own avatar/, avatar.png and assistant-name.txt (written by
// install.sh: the Korean name, then the English one). The one in use is named in the file
// "persona" (none means the main one). An assistant with no clips and no photo yet shows its name
// on a soft circle instead.

import AppKit

let mainPersonaID = "main"

struct Persona: Equatable {
    let id: String
    let nameKorean: String
    let nameEnglish: String
    let folder: URL
}

/// The names in assistant-name.txt: Korean on the first line, English on the second.
func parsePersonaNames(_ text: String) -> (korean: String, english: String)? {
    let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    guard let korean = lines.first else { return nil }
    return (korean, lines.dropFirst().first ?? korean)
}

private func persona(id: String, folder: URL) -> Persona {
    let text = (try? String(contentsOf: folder.appendingPathComponent("assistant-name.txt"), encoding: .utf8)) ?? ""
    let names = parsePersonaNames(text) ?? (id == mainPersonaID ? ("비서", "Assistant") : (id, id))
    return Persona(id: id, nameKorean: names.korean, nameEnglish: names.english, folder: folder)
}

/// The main assistant first, then every folder in personas/ that has a persona.conf, by name.
func personaList(base: URL) -> [Persona] {
    let personas = base.appendingPathComponent("personas")
    let names = (try? FileManager.default.contentsOfDirectory(atPath: personas.path)) ?? []
    let extra = names.sorted().filter {
        FileManager.default.fileExists(atPath: personas.appendingPathComponent("\($0)/persona.conf").path)
    }
    return [persona(id: mainPersonaID, folder: base)]
        + extra.map { persona(id: $0, folder: personas.appendingPathComponent($0)) }
}

/// The assistant in use: the one named in "persona", else the main one.
func chosenPersona(base: URL) -> Persona {
    let all = personaList(base: base)
    let chosen = ((try? String(contentsOf: base.appendingPathComponent("persona"), encoding: .utf8)) ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return all.first { $0.id == chosen } ?? all[0]
}

/// Saves the choice for the scripts and the listener.
func savePersonaChoice(_ id: String, base: URL) {
    do {
        try "\(id)\n".write(to: base.appendingPathComponent("persona"), atomically: true, encoding: .utf8)
    } catch {
        NSLog("assistant_avatar: cannot save the assistant choice: \(error.localizedDescription)")
    }
}

/// A stand-in photo for an assistant with no clips or photo yet: its name on a soft gradient circle.
func placeholderPhoto(name: String, side: CGFloat) -> NSImage {
    NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
        let gradient = NSGradient(colors: [NSColor(calibratedRed: 0.55, green: 0.47, blue: 0.86, alpha: 1),
                                           NSColor(calibratedRed: 0.95, green: 0.55, blue: 0.68, alpha: 1)])
        gradient?.draw(in: NSBezierPath(ovalIn: rect), angle: -60)
        let font = NSFont.systemFont(ofSize: side * (name.count > 2 ? 0.2 : 0.26), weight: .semibold)
        let words = NSAttributedString(string: name, attributes: [.font: font, .foregroundColor: NSColor.white])
        let size = words.size()
        words.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
        return true
    }
}

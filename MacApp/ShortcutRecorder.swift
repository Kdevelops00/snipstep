import SwiftUI
import Carbon

struct ShortcutRecorder: NSViewRepresentable {
    let label: String
    let changed: (UInt32, UInt32, String) -> Void
    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.bezelStyle = .rounded
        button.target = button; button.action = #selector(RecorderButton.begin)
        return button
    }
    func updateNSView(_ button: RecorderButton, context: Context) {
        if !button.recording { button.title = label + " · Change" }
        button.changed = changed
    }
}

final class RecorderButton: NSButton {
    var recording = false
    var savedTitle = "Choose shortcut"
    var changed: ((UInt32, UInt32, String) -> Void)?
    override var acceptsFirstResponder: Bool { true }
    @objc func begin() { savedTitle = title; recording = true; title = "Press shortcut · Esc cancels"; window?.makeFirstResponder(self) }
    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        if event.keyCode == 53 { recording = false; title = savedTitle; return }
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        guard (flags.contains(.command) || flags.contains(.control)), flags.rawValue.nonzeroBitCount >= 2,
              let key = event.charactersIgnoringModifiers?.uppercased(), key.count == 1,
              key.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) }) else {
            title = "Use two modifiers + a letter or number"; return
        }
        var modifiers: UInt32 = 0
        var label = ""
        for (flag, carbon, symbol) in [(NSEvent.ModifierFlags.control, controlKey, "⌃"), (.option, optionKey, "⌥"), (.shift, shiftKey, "⇧"), (.command, cmdKey, "⌘")] {
            if flags.contains(flag) { modifiers |= UInt32(carbon); label += symbol }
        }
        recording = false
        changed?(UInt32(event.keyCode), modifiers, label + key)
    }
    override func resignFirstResponder() -> Bool { if recording { title = savedTitle }; recording = false; return super.resignFirstResponder() }
}

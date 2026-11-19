import Carbon

/// Carbon registers only this chord; no keyboard monitoring or Accessibility access.
@MainActor final class CaptureHotKey {
    private var hotKey: EventHotKeyRef?
    private var current: (UInt32, UInt32)?
    private var handler: EventHandlerRef?

    func register(keyCode: UInt32 = UInt32(kVK_ANSI_X), modifiers: UInt32 = UInt32(controlKey | optionKey)) -> Bool {
        if let current, current.0 == keyCode && current.1 == modifiers { return true }
        if handler == nil {
            var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                var identifier = EventHotKeyID()
                guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                        nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier) == noErr,
                      identifier.signature == 0x534E4150, identifier.id == 1 else { return OSStatus(eventNotHandledErr) }
                Task { @MainActor in AppModel.shared?.capture() }
                return noErr
            }, 1, &type, nil, &handler)
            guard installed == noErr else { return false }
        }
        var replacement: EventHotKeyRef?
        let result = RegisterEventHotKey(keyCode, modifiers,
                                        EventHotKeyID(signature: 0x534E4150, id: 1),
                                        GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &replacement)
        if result == noErr {
            if let hotKey { UnregisterEventHotKey(hotKey) }
            hotKey = replacement
            current = (keyCode, modifiers)
        }
        return result == noErr
    }
}

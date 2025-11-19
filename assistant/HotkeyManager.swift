import Foundation
import Carbon
import AppKit

class HotkeyManager: ObservableObject {
    private var eventHandler: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private let hotKeyID = EventHotKeyID(signature: FourCharCode(fromString: "TXTX"), id: 1)

    var onHotkeyPressed: (() -> Void)?

    init() {
        registerHotkey()
    }

    deinit {
        unregisterHotkey()
    }

    private func registerHotkey() {
        // Register Command + Shift + E as the hotkey
        let keyCode: UInt32 = 14 // E key
        let modifiers: UInt32 = UInt32(cmdKey | shiftKey)

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))

        // Install event handler
        InstallEventHandler(GetApplicationEventTarget(), { (nextHandler, theEvent, userData) -> OSStatus in
            guard let userData = userData else { return noErr }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()

            var hotKeyID = EventHotKeyID()
            GetEventParameter(theEvent,
                            EventParamName(kEventParamDirectObject),
                            EventParamType(typeEventHotKeyID),
                            nil,
                            MemoryLayout<EventHotKeyID>.size,
                            nil,
                            &hotKeyID)

            if hotKeyID.id == manager.hotKeyID.id {
                DispatchQueue.main.async {
                    manager.onHotkeyPressed?()
                }
            }

            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)

        // Register the hotkey
        var hotKeyRef: EventHotKeyRef?
        RegisterEventHotKey(keyCode,
                          modifiers,
                          hotKeyID,
                          GetApplicationEventTarget(),
                          0,
                          &hotKeyRef)
        self.hotKeyRef = hotKeyRef
    }

    private func unregisterHotkey() {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandler = eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }
}

// Helper to convert String to FourCharCode
private func FourCharCode(fromString string: String) -> FourCharCode {
    var result: FourCharCode = 0
    for char in string.utf8.prefix(4) {
        result = (result << 8) + FourCharCode(char)
    }
    return result
}

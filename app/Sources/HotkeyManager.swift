import Carbon
import AppKit

/// Global variable for the callback (needed for C function pointer compatibility)
private var hotkeyCallback: (() -> Void)?

class HotkeyManager {
    static let shared = HotkeyManager()
    private var hotKeyRef: EventHotKeyRef?

    /// Register Cmd+Shift+M as the global hotkey
    func register(callback: @escaping () -> Void) {
        hotkeyCallback = callback

        let hotKeyID = EventHotKeyID(
            signature: OSType(0x444D5558),  // "DMUX"
            id: 1
        )

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_: EventHandlerCallRef?, _: EventRef?, _: UnsafeMutableRawPointer?) -> OSStatus in
                hotkeyCallback?()
                return noErr
            },
            1,
            &eventType,
            nil,
            nil
        )

        // Key code 46 = 'M', cmdKey | shiftKey
        RegisterEventHotKey(
            46,
            UInt32(cmdKey | shiftKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }
}

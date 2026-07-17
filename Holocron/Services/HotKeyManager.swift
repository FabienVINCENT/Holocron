import AppKit
import Carbon.HIToolbox

/// Global hotkeys via Carbon RegisterEventHotKey: works without Accessibility
/// permission and swallows the keystroke (it never reaches the focused app).
///
/// Decision keys (⌘Y / ⌘N / ⌘1…⌘4) are registered ONLY while a card is
/// pending, then released — outside that window the shortcuts belong to the
/// focused app as usual.
@MainActor
final class HotKeyManager {
    typealias Handler = () -> Void

    private struct Registration {
        let ref: EventHotKeyRef
        let handler: Handler
    }

    private var registrations: [UInt32: Registration] = [:]
    private var nextId: UInt32 = 1
    private var eventHandler: EventHandlerRef?
    private static let signature: OSType = 0x484C4352  // 'HLCR'

    init() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return noErr }
            var hotKeyID = EventHotKeyID()
            GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            Task { @MainActor in
                manager.fire(id: hotKeyID.id)
            }
            return noErr
        }
        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }

    private func fire(id: UInt32) {
        registrations[id]?.handler()
    }

    /// Returns a token to pass to `unregister`.
    @discardableResult
    func register(keyCode: Int, carbonModifiers: Int, handler: @escaping Handler) -> UInt32? {
        let id = nextId
        nextId += 1
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(
            UInt32(keyCode),
            UInt32(carbonModifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else { return nil }
        registrations[id] = Registration(ref: ref, handler: handler)
        return id
    }

    func unregister(_ token: UInt32) {
        guard let registration = registrations.removeValue(forKey: token) else { return }
        UnregisterEventHotKey(registration.ref)
    }

    func unregisterAll(_ tokens: [UInt32]) {
        tokens.forEach(unregister)
    }
}

/// Carbon key codes / modifiers used by Holocron.
enum Keys {
    static let h = kVK_ANSI_H
    static let y = kVK_ANSI_Y
    static let n = kVK_ANSI_N
    static let one = kVK_ANSI_1
    static let two = kVK_ANSI_2
    static let three = kVK_ANSI_3
    static let four = kVK_ANSI_4
    static let cmd = cmdKey
    static let controlOption = controlKey | optionKey
}

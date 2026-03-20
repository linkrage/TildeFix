import Foundation
import CoreGraphics
import Carbon

let iso_section: CGKeyCode = 0x0A  // keycode 10: ISO key left of 1
let grave_tilde: CGKeyCode = 0x32  // keycode 50: ANSI grave/tilde

// Track Cmd+Shift state for layout switching
var cmdShiftDown = false
var otherKeyPressed = false

func switchToNextInputSource() {
    guard let sourceList = TISCreateInputSourceList(
        [kTISPropertyInputSourceIsEnabled: true, kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource!] as CFDictionary,
        false
    )?.takeRetainedValue() as? [TISInputSource] else { return }

    // Filter to only keyboard layouts (not input methods)
    let keyboards = sourceList.filter { source in
        guard let category = TISGetInputSourceProperty(source, kTISPropertyInputSourceCategory) else { return false }
        let cat = Unmanaged<CFString>.fromOpaque(category).takeUnretainedValue() as String
        return cat == (kTISCategoryKeyboardInputSource as String)
    }

    guard keyboards.count > 1 else { return }

    // Find current
    guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return }
    let currentID: String
    if let idPtr = TISGetInputSourceProperty(current, kTISPropertyInputSourceID) {
        currentID = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
    } else {
        currentID = ""
    }

    // Find index of current and select next
    var currentIndex = 0
    for (i, kb) in keyboards.enumerated() {
        if let idPtr = TISGetInputSourceProperty(kb, kTISPropertyInputSourceID) {
            let id = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
            if id == currentID {
                currentIndex = i
                break
            }
        }
    }

    let nextIndex = (currentIndex + 1) % keyboards.count
    TISSelectInputSource(keyboards[nextIndex])
}

func callback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let refcon = refcon {
            let tap = Unmanaged<CFMachPort>.fromOpaque(refcon).takeUnretainedValue()
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passRetained(event)
    }

    let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))

    // --- Key remap: ISO section → grave/tilde ---
    if type == .keyDown || type == .keyUp {
        if keyCode == iso_section {
            event.setIntegerValueField(.keyboardEventKeycode, value: Int64(grave_tilde))
        }
        // Any key pressed while Cmd+Shift is held = not a bare Cmd+Shift tap
        if cmdShiftDown {
            otherKeyPressed = true
        }
    }

    // --- Cmd+Shift layout switching ---
    if type == .flagsChanged {
        let flags = event.flags
        let hasCmd = flags.contains(.maskCommand)
        let hasShift = flags.contains(.maskShift)

        if hasCmd && hasShift && !cmdShiftDown {
            // Cmd+Shift just pressed together
            cmdShiftDown = true
            otherKeyPressed = false
        } else if cmdShiftDown && !(hasCmd && hasShift) {
            // Cmd+Shift released
            if !otherKeyPressed {
                switchToNextInputSource()
            }
            cmdShiftDown = false
            otherKeyPressed = false
        }
    }

    return Unmanaged.passRetained(event)
}

let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue) |
                              (1 << CGEventType.keyUp.rawValue) |
                              (1 << CGEventType.flagsChanged.rawValue)

guard let tap = CGEvent.tapCreate(
    tap: .cgSessionEventTap,
    place: .headInsertEventTap,
    options: .defaultTap,
    eventsOfInterest: eventMask,
    callback: callback,
    userInfo: nil
) else {
    print("ERROR: Failed to create event tap. Grant Accessibility/Input Monitoring permission.")
    exit(1)
}

CGEvent.tapEnable(tap: tap, enable: true)

let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)

print("TildeFix active:")
print("  - ISO section (keycode 10) → grave/tilde (keycode 50)")
print("  - Cmd+Shift → rotate input source")

CFRunLoopRun()

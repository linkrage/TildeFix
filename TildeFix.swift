import Foundation
import CoreGraphics
import Carbon
import Cocoa

let iso_section: CGKeyCode = 0x0A  // keycode 10: ISO key left of 1
let grave_tilde: CGKeyCode = 0x32  // keycode 50: ANSI grave/tilde

var cmdShiftDown = false
var otherKeyPressed = false

let setupDoneFile = (NSHomeDirectory() as NSString).appendingPathComponent(".config/tildefix/setup_done")

// MARK: - Setup state

func isSetupDone() -> Bool {
    FileManager.default.fileExists(atPath: setupDoneFile)
}

func markSetupDone() {
    let dir = (setupDoneFile as NSString).deletingLastPathComponent
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: setupDoneFile, contents: nil)
}

// MARK: - Custom blur popup

func showPopup(title: String, body: String, buttonTitle: String = "Let's go") {
    var done = false
    DispatchQueue.main.async {
        NSApp.activate(ignoringOtherApps: true)

        let width: CGFloat = 480
        let height: CGFloat = 340

        let screen = NSScreen.main!.frame
        let x = (screen.width - width) / 2
        let y = (screen.height - height) / 2

        let window = NSPanel(
            contentRect: NSRect(x: x, y: y, width: width, height: height),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.level = .floating
        window.backgroundColor = .clear

        let blur = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        blur.blendingMode = .behindWindow
        blur.material = .hudWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 16
        window.contentView = blur

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 20, weight: .bold)
        titleLabel.textColor = .labelColor
        titleLabel.frame = NSRect(x: 32, y: height - 60, width: width - 64, height: 30)
        blur.addSubview(titleLabel)

        let bodyLabel = NSTextField(wrappingLabelWithString: body)
        bodyLabel.font = NSFont.systemFont(ofSize: 14)
        bodyLabel.textColor = .secondaryLabelColor
        bodyLabel.frame = NSRect(x: 32, y: 70, width: width - 64, height: height - 140)
        bodyLabel.isSelectable = false
        blur.addSubview(bodyLabel)

        let button = NSButton(title: buttonTitle, target: nil, action: nil)
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        button.frame = NSRect(x: (width - 200) / 2, y: 20, width: 200, height: 36)
        button.keyEquivalent = "\r"
        let clickHandler = ClickHandler { done = true; window.close() }
        button.target = clickHandler
        button.action = #selector(ClickHandler.clicked)
        objc_setAssociatedObject(button, "handler", clickHandler, .OBJC_ASSOCIATION_RETAIN)
        blur.addSubview(button)

        window.makeKeyAndOrderFront(nil)
    }
    while !done {
        Thread.sleep(forTimeInterval: 0.05)
    }
}

class ClickHandler: NSObject {
    let action: () -> Void
    init(action: @escaping () -> Void) { self.action = action }
    @objc func clicked() { action() }
}

// MARK: - Permission helpers

func openAccessibilitySettings() {
    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
}

func openInputMonitoringSettings() {
    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
}

func openLoginItemsSettings() {
    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
}

func tryCreateEventTap() -> CFMachPort? {
    let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue) |
                                  (1 << CGEventType.keyUp.rawValue) |
                                  (1 << CGEventType.flagsChanged.rawValue)

    return CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: eventMask,
        callback: eventCallback,
        userInfo: nil
    )
}

// MARK: - Input source switching

func switchToNextInputSource() {
    guard let sourceList = TISCreateInputSourceList(
        [kTISPropertyInputSourceIsEnabled: true, kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource!] as CFDictionary,
        false
    )?.takeRetainedValue() as? [TISInputSource] else { return }

    let keyboards = sourceList.filter { source in
        guard let category = TISGetInputSourceProperty(source, kTISPropertyInputSourceCategory) else { return false }
        let cat = Unmanaged<CFString>.fromOpaque(category).takeUnretainedValue() as String
        return cat == (kTISCategoryKeyboardInputSource as String)
    }

    guard keyboards.count > 1 else { return }

    guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return }
    let currentID: String
    if let idPtr = TISGetInputSourceProperty(current, kTISPropertyInputSourceID) {
        currentID = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
    } else {
        currentID = ""
    }

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

// MARK: - Event tap callback

func eventCallback(
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

    if type == .keyDown || type == .keyUp {
        if keyCode == iso_section {
            event.setIntegerValueField(.keyboardEventKeycode, value: Int64(grave_tilde))
        }
        if cmdShiftDown {
            otherKeyPressed = true
        }
    }

    if type == .flagsChanged {
        let flags = event.flags
        let hasCmd = flags.contains(.maskCommand)
        let hasShift = flags.contains(.maskShift)

        if hasCmd && hasShift && !cmdShiftDown {
            cmdShiftDown = true
            otherKeyPressed = false
        } else if cmdShiftDown && !(hasCmd && hasShift) {
            if !otherKeyPressed {
                switchToNextInputSource()
            }
            cmdShiftDown = false
            otherKeyPressed = false
        }
    }

    return Unmanaged.passRetained(event)
}

// MARK: - Setup flow

func startEventTap(_ tap: CFMachPort) {
    CGEvent.tapEnable(tap: tap, enable: true)
    let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)

    print("""

    ══════════════════════════════════════════
    TildeFix is running.
      § → `    ± → ~    Cmd+Shift → switch layout
    ══════════════════════════════════════════
    """)
}

func runSetupFlow() {
    let needsAccessibility = !AXIsProcessTrusted()
    let needsSetup = !isSetupDone()

    print("""

    ╔══════════════════════════════════════════╗
    ║           TildeFix v1.0.1               ║
    ║   § → `  and  ± → ~  on ISO keyboards  ║
    ╚══════════════════════════════════════════╝
    """)

    // Already fully set up — just start
    if !needsAccessibility && !needsSetup {
        if let tap = tryCreateEventTap() {
            print("    ✓ All permissions granted\n")
            startEventTap(tap)
            return
        }
    }

    // Show welcome popup
    if needsSetup {
        showPopup(
            title: "TildeFix — Quick Setup",
            body: """
            Welcome! 3 quick steps to fix your § key:

            Step 1  Grant Accessibility permission
            Step 2  Grant Input Monitoring permission
            Step 3  Add to Login Items (auto-start)

            For each step, System Settings will open automatically.
            Just click + then find TildeFix and toggle it ON.
            """
        )
    }

    // Step 1: Accessibility
    if !AXIsProcessTrusted() {
        print("    Step 1/3: Waiting for Accessibility...")
        DispatchQueue.main.async { openAccessibilitySettings() }
        while !AXIsProcessTrusted() {
            Thread.sleep(forTimeInterval: 1)
        }
        print("    ✓ Accessibility granted!\n")
    } else {
        print("    ✓ Accessibility — already granted\n")
    }

    // Step 2: Input Monitoring
    if needsSetup {
        print("    Step 2/3: Input Monitoring...")
        DispatchQueue.main.async { openInputMonitoringSettings() }

        showPopup(
            title: "Step 2/3: Input Monitoring",
            body: """
            System Settings is now open.

            Click + then find TildeFix and toggle it ON.

            When done, come back here and click Continue.
            If TildeFix is already listed, just click Continue.
            """,
            buttonTitle: "Continue"
        )
        print("    ✓ Input Monitoring step done\n")
    }

    // Start the event tap
    guard let tap = tryCreateEventTap() else {
        print("    ERROR: Could not create event tap. Please check permissions and restart.")
        showPopup(
            title: "Permission Error",
            body: """
            TildeFix could not start the key remapper.

            Please make sure both Accessibility and Input Monitoring
            permissions are granted, then restart TildeFix.
            """,
            buttonTitle: "Quit"
        )
        exit(1)
    }
    startEventTap(tap)

    // Step 3: Login Items
    if needsSetup {
        showPopup(
            title: "Step 3/3: Auto-start on login",
            body: """
            Almost done!

            Login Items will open next.
            Click + then find TildeFix and click Add.

            This ensures TildeFix starts automatically
            after every reboot so you never lose your
            ` and ~ keys.
            """,
            buttonTitle: "Open Login Items"
        )
        DispatchQueue.main.async { openLoginItemsSettings() }
        markSetupDone()
        print("    ✓ Setup complete!\n")
    }
}

// MARK: - Self-relaunch on quit during setup

func relaunchSelf() {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    task.arguments = ["-a", Bundle.main.bundlePath]
    task.standardOutput = nil
    task.standardError = nil
    try? task.run()
}

// MARK: - Main

let app = NSApplication.shared
app.setActivationPolicy(.regular)

// If setup isn't done, relaunch on termination (e.g. Quit & Reopen from Settings)
if !isSetupDone() {
    atexit {
        if !isSetupDone() {
            relaunchSelf()
        }
    }
}

// Delay setup slightly to ensure app is fully launched after a Quit & Reopen
DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
    runSetupFlow()
    DispatchQueue.main.async {
        app.setActivationPolicy(.accessory)
    }
}

app.run()

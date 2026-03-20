# TildeFix

Fix the `§` / `±` key on UK/ISO Mac keyboards — get `` ` `` (backtick) and `~` (tilde) where they belong.

A lightweight macOS utility for UK/ISO MacBook users who need US-style tilde/backtick behavior. Also fixes the same key for Bulgarian Phonetic and other layouts.

## The Problem

If you have a **UK (ISO) MacBook** and use a **US keyboard layout**, the key left of `1` produces `§` and `±` instead of `` ` `` and `~`. This makes working in the terminal painful — backtick and tilde are essential for bash, markdown, and many programming languages.

This also affects **Bulgarian Phonetic** layout users, where the same key should produce `ч` / `Ч`.

Tools like [Karabiner-Elements](https://github.com/pqrs-org/Karabiner-Elements) can fix this, but as of macOS 26 (Tahoe), Karabiner's driver extension is broken ([#4299](https://github.com/pqrs-org/Karabiner-Elements/issues/4299), [#4314](https://github.com/pqrs-org/Karabiner-Elements/issues/4314), [#4376](https://github.com/pqrs-org/Karabiner-Elements/issues/4376)). Neither `hidutil` nor keyboard type overrides work reliably on macOS 26 for this key.

## The Solution

TildeFix is a single-file Swift program (~100 lines) that uses a `CGEventTap` to:

1. **Remap the ISO section key** (keycode 10) to the ANSI grave/tilde key (keycode 50) — fixing `` ` `` and `~` on any layout
2. **Rotate input sources with Cmd+Shift** — press Cmd+Shift (without any other key) to cycle through your enabled keyboard layouts

This operates at the CoreGraphics event level, so it works with:
- All keyboard layouts (US, Bulgarian Phonetic, etc.)
- All keyboard shortcuts (Cmd+`` ` `` window switching works correctly)
- Any application

## Requirements

- macOS 13+ (tested on macOS 26 Tahoe)
- Apple Silicon or Intel Mac with an ISO keyboard

## Installation

### Homebrew (recommended)

```bash
brew tap linkrage/tildefix
brew install --cask tildefix
```

### Build from source

Requires Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/linkrage/TildeFix.git
cd TildeFix
make install
```

## Setup

On first launch, TildeFix guides you through 3 quick steps with a built-in setup wizard:

1. **Accessibility** — System Settings opens automatically, click `+` → find TildeFix → toggle ON
2. **Input Monitoring** — same process, next settings page opens automatically
3. **Login Items** — add TildeFix so it starts automatically after every reboot

Just run the app and follow the prompts:

```bash
open ~/Applications/TildeFix.app       # if built from source
open /Applications/TildeFix.app        # if installed via Homebrew
```

## Uninstall

### Homebrew

```bash
brew uninstall --cask tildefix
```

### From source

```bash
make uninstall
```

Then remove TildeFix from Accessibility and Input Monitoring in System Settings.

## How It Works

TildeFix creates a `CGEventTap` that intercepts keyboard events at the session level:

- **Key remap**: When keycode 10 (ISO section key: `§`/`±`) is detected on `keyDown` or `keyUp`, it's rewritten to keycode 50 (ANSI grave/tilde: `` ` ``/`~`). The keyboard layout then interprets keycode 50 normally — producing `` ` ``/`~` on US layout, `ч`/`Ч` on Bulgarian Phonetic, etc.

- **Layout switching**: When Cmd+Shift are pressed and released together (without any other key in between), the next enabled keyboard input source is selected via the `TISSelectInputSource` API.

## Why not...

| Alternative | Problem on macOS 26 |
|---|---|
| Karabiner-Elements | Driver extension broken on macOS 26 ([multiple issues](https://github.com/pqrs-org/Karabiner-Elements/issues/4299)) |
| `hidutil` UserKeyMapping | Silently fails for this specific key on macOS 26 |
| `com.apple.keyboardtype` plist | Keyboard type override has no effect on macOS 26 |
| Custom `.keylayout` file | Works for typing but breaks Cmd+`` ` `` window switching (shortcuts use keycodes, not characters) |
| App Store distribution | Not possible — `CGEventTap` requires Accessibility permissions which are blocked by App Store sandboxing |

## Keywords

mac tilde fix, mac backtick wrong key, UK ISO keyboard § section sign, macOS grave accent, swap § backtick mac, Karabiner alternative macOS 26, mac terminal tilde not working

## License

MIT

# TV Remote by Chyri 📺

> **A modern, lightweight Windows tray application to control Android TV and Google TV devices.**

Control your Android & Google TV right from your Windows system tray. Features live screen mirroring in an always-on-top window, typing directly from your PC physical keyboard, quick app launches, now-playing media metadata, full remote navigation, and built-in ADB tools with auto-discovery. Lightweight, secure, and multi-device ready.

*(Android companion app coming soon!)*

---

## ✨ Features

- 🔹 **Windows System Tray Integration**: Unobtrusive icon next to the taskbar clock. Left-click to open the control flyout; right-click for quick actions (open, settings, exit).
- 🔹 **Acrylic Flyout UI**: Floats right above your Windows taskbar with smooth animations, rounded corners, and native light/dark theme adaptation matching Windows 11 aesthetics.
- 🔹 **Live Screen Mirroring**:
  - **Cast Media Mode**: Real-time album art, media title, and player status.
  - **ADB Screen Mode**: Real-time continuous TV screen mirroring.
  - **Pop-out Window**: Pop out the mirror feed into a standalone, resizable, always-on-top floating window with compact mode and aspect ratio locking.
- 🔹 **Smart TV Keyboard with Real-time Typing**:
  - Type directly on your TV using your computer's physical keyboard.
  - Automatic detection of active input fields (IME) on the TV.
  - Automatic delta-typing and manual send modes.
- 🔹 **Complete Remote Control**:
  - Directional D-Pad (Up, Down, Left, Right) + center Select/OK.
  - Back, Home, Menu, and Power (standby/wake).
  - Volume control (+ / - with rapid hold repetition, percentage indicator, and mute toggle).
  - Media playback: Play, Pause, Rewind, Fast-Forward, Previous, and Next.
- 🔹 **Quick App Launcher**:
  - Reorderable, toggleable one-click shortcuts for your favorite streaming apps: **YouTube**, **Netflix**, **Disney+**, **Max**, and **Settings**, plus support for custom apps.
- 🔹 **Built-in ADB Tools & Terminal**:
  - Integrated terminal console for diagnostics and raw command execution.
  - Native support for **Minimal ADB and Fastboot** and automatic platform-tools downloader from official Google sources.
  - Customizable port configuration (default 5555 and dynamic ports).
- 🔹 **Zero-Configuration Network Discovery (mDNS)**:
  - Automatically discovers Android TV and Google TV devices on your local Wi-Fi/Ethernet network.
  - Multi-TV support with instant device switching.
  - Persistent TLS pairing: PINs are securely saved locally so you only ever have to pair once.
- 🔹 **Physical Keyboard Navigation**:
  - Arrow keys: Navigate TV D-pad
  - `Enter`: Select / OK
  - `Esc` / `Backspace`: Back
  - `Home`: Home
  - `+` / `-`: Volume up / down
- 🌐 **Multilingual & System Theming**:
  - Automatically matches your system language with native support for **English**, **Portuguese (Português)**, and **Spanish (Español)**.
  - Automatic Dark/Light mode following your Windows theme.

---

## 🚀 Getting Started

### Prerequisites

1. **Flutter SDK** (3.24+ recommended).
2. **Windows Developer Mode** enabled (required for symlinks in native C++ desktop plugins):
   - Open Windows Settings (`Win + I`) > **Privacy & Security** > **For developers**.
   - Enable **Developer Mode**.

### Running in Development

```bash
flutter run -d windows
```

### Building for Production (Standalone .exe)

```bash
flutter build windows --release
```

The compiled standalone executable will be located at:
`build\windows\x64\runner\Release\tv_remote.exe`

---

## 🌍 Contributing & Localization

All interface strings are localized using the standard Flutter ARB format:
- `lib/l10n/app_en.arb` (English - default)
- `lib/l10n/app_pt.arb` (Portuguese)
- `lib/l10n/app_es.arb` (Spanish)

To contribute translations for a new language (e.g. French `app_fr.arb` or German `app_de.arb`):
1. Duplicate `app_en.arb` and rename it to `app_<locale>.arb`.
2. Translate the values while preserving the keys.
3. Run `flutter gen-l10n`.

---

## 📄 License

This project is dedicated to the public domain under the **Creative Commons CC0 1.0 Universal** License. See the [LICENSE](LICENSE) file for full details.

---

Made with ❤️ by [Chyri](https://www.chyri.com.br/)

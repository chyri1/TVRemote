# TV Remote by Chyri 📺

> **A modern, fast, and lightweight controller for Android TV and Google TV devices — natively built for Android & Windows.**

Control your Android TV & Google TV directly from your **Android smartphone** or from your **Windows system tray**. Enjoy live screen mirroring, direct physical keyboard typing (Windows), voice assistant integration, quick app switching, now-playing media metadata, full remote navigation, and zero-configuration ADB tools.

---

## ✨ Features

### 📱 Android Experience
- 🔹 **Built-in Pure ADB Client**: Zero external downloads needed on mobile. Features a pure Dart cryptographic engine with RSA key generation and TV authorization.
- 🔹 **Embedded Live Mirror Card**: Low-latency screen mirror directly inside the app with status indicators, loading states, and black frame DRM filtering.
- 🔹 **Voice & Assistant Control**: Direct voice search and Assistant activation using your device's microphone.
- 🔹 **Optimized Mobile UX**: Pinned top bar for seamless navigation, smooth scrolling, haptic feedback, and modern adaptive icon (`#2F56CD`).

### 💻 Windows Experience
- 🔹 **System Tray Integration**: Unobtrusive icon next to the taskbar clock. Left-click to open the control flyout; right-click for quick actions (open, settings, exit).
- 🔹 **Acrylic Flyout UI**: Floats right above your taskbar with smooth animations, rounded corners, and native light/dark theme adaptation matching Windows 11 aesthetics.
- 🔹 **Pop-Out Mirror Window**: Detach the TV mirror feed into an always-on-top, resizable floating desktop window with aspect ratio locking.
- 🔹 **Physical Keyboard Navigation & Typing**:
  - Type directly on your TV with your PC keyboard (with IME field detection and delta typing).
  - Arrow keys: Navigate TV D-pad | `Enter`: Select / OK | `Esc`/`Backspace`: Back | `Home`: Home | `+`/`-`: Volume.
- 🔹 **Automated ADB Setup**: 1-click official Google platform-tools downloader or automatic detection of Minimal ADB and Fastboot.

### 🌐 Cross-Platform Core Features
- 🎛️ **Complete Remote Navigation**: Directional D-Pad with center Select/OK, Home, Back, Menu, Power (standby/wake), and Volume control (+ / - with rapid hold repetition and mute toggle).
- 📺 **Media & Cast Metadata**: Real-time album art, media title, artist, and player controls (Play, Pause, Fast-Forward, Rewind, Previous, Next).
- 🚀 **Quick App Launcher**: One-click shortcuts for your favorite streaming apps: **YouTube**, **Netflix**, **Disney+**, **Max**, **Prime Video**, and **Settings**, plus custom app support.
- 🔍 **Zero-Configuration Discovery (mDNS)**: Automatically detects TVs on your local Wi-Fi/Ethernet network. PIN pairing is securely stored so you only pair once.
- 🌍 **Multilingual Out-of-the-Box**: Native support for **English**, **Português (Brasil)**, and **Español**, automatically following system preferences.

---

## 📦 Downloads & Installation

Pre-built binaries are available on the [**Releases**](https://github.com/chyri1/TVRemote/releases) page:

| Platform | File | Description |
| :--- | :--- | :--- |
| **Android** | `TVRemote-Android-v1.0.0.apk` | Standalone universal APK for Android 5.0+ phones & tablets |
| **Windows** | `TVRemote-Windows-v1.0.0.exe` | Lightweight user installer for Windows 10/11 (no admin rights required) |

---

## 🚀 Development & Building

### Prerequisites
- **Flutter SDK** (3.24+ recommended)
- **Android SDK** (for Android builds) or **Visual Studio C++ / Developer Mode** (for Windows builds)

### Running Locally

```bash
# Run on connected Android device / emulator
flutter run -d android

# Run on Windows desktop
flutter run -d windows
```

### Building Release Binaries

```bash
# Build Android Release APK
flutter build apk --release
# Output: build/app/outputs/flutter-apk/app-release.apk

# Build Windows Release Executable
flutter build windows --release
# Output: build/windows/x64/runner/Release/tv_remote.exe
```

---

## 🌍 Contributing & Localization

All interface strings are localized using Flutter ARB files located in `lib/l10n/`:
- `lib/l10n/app_en.arb` (English - default)
- `lib/l10n/app_pt.arb` (Portuguese)
- `lib/l10n/app_es.arb` (Spanish)

To add a new language:
1. Copy `app_en.arb` to `app_<locale>.arb` (e.g., `app_fr.arb`).
2. Translate the string values while keeping the keys identical.
3. Run `flutter gen-l10n`.

---

## 📄 License

This project is dedicated to the public domain under the **Creative Commons CC0 1.0 Universal** License. See the [LICENSE](LICENSE) file for details.

---

Made with ❤️ by [Chyri](https://www.chyri.com.br/)

# Zanoza

iOS client for [MasterDnsVPN](https://github.com/masterking32/MasterDnsVPN) — a DNS-tunneling VPN for high-censorship networks.

It wraps the upstream MasterDnsVPN Go client into an iOS app, exposes its local SOCKS5 proxy at `127.0.0.1:41080`, and keeps the tunnel running while you switch to another app (Shadowrocket, Happ, etc.) that runs the proxy.
The app does **not** create an iOS VPN profile, since it is unsigned.

Special thanks to [plumbicon](https://github.com/plumbicon/godwit), as their UI was used as a foundation.

## Repository layout

```
Zanoza/
├── apple/                            # Xcode / SwiftPM project
│   ├── Package.swift                 # ZanozaKit shared library
│   ├── project.yml                   # XcodeGen project definition
│   ├── Frameworks/                   # Mobile.xcframework lands here
│   ├── Scripts/
│   │   ├── build-xcframework.sh         # gomobile bind → Mobile.xcframework
│   │   ├── build-ios-unsigned-local-ipa.sh
│   │   ├── prepare-xcode.sh             # xcodegen wrapper
│   │   └── generate-icon.py             # AppIcon generator (Pillow)
│   ├── Sources/
│   │   ├── ZanozaApp/            # iOS app target
│   │   │   ├── Assets.xcassets/AppIcon.appiconset/
│   │   │   ├── Info.plist            # UIBackgroundModes=[audio]
│   │   │   └── ZanozaApp.swift
│   │   └── ZanozaKit/            # Shared SwiftPM library
│   │       ├── Models/               # ConnectionProfile, ClientStatus
│   │       ├── Services/             # MasterDnsEngine, BackgroundRuntimeKeeper, …
│   │       ├── ViewModels/           # ClientViewModel
│   │       ├── Views/                # ContentView, ImportProfileSheet, …
│   │       └── Resources/{en,ru}.lproj/Localizable.strings
│   └── Tests/ZanozaKitTests/
└── masterdns/                        # Vendored MasterDnsVPN fork
    ├── go.mod                        # adds golang.org/x/mobile dep
    └── mobile/                       # gomobile-bindable wrapper package
        ├── mobile.go                 #   Start/Stop/IsRunning/SetLogWriter
        └── stdout_pump.go            #   forwards stdout → LogWriter
```

## Prerequisites

- macOS 14 + Xcode 16 (the iOS toolchain ships with Xcode)
- [Homebrew](https://brew.sh)
- `brew install go xcodegen`
- `go install golang.org/x/mobile/cmd/gomobile@latest && gomobile init`
- Python 3 with Pillow (`python3 -m pip install --user pillow`) — only needed if you want to regenerate the AppIcon

## Build

```bash
# 1. Build the Go xcframework
apple/Scripts/build-xcframework.sh

# 2. Generate the Xcode project
apple/Scripts/prepare-xcode.sh

# 3. Build an unsigned IPA
apple/Scripts/build-ios-unsigned-local-ipa.sh
#   → apple/.build/ios-unsigned-local/Zanoza-unsigned.ipa
```

The IPA is unsigned. Sign and install it on a device using:

- **[Sideloadly](https://sideloadly.io)** — drop the IPA in, sign with your Apple ID, install via USB. Free Apple ID profiles expire every 7 days; a paid Apple Developer account ($99/yr) gets 1-year profiles.
- **AltStore / SideStore** — install on-device, no Mac needed for re-signing after the first push.

Enable **Settings → Privacy & Security → Developer Mode** on the iPhone before the first install.

## Usage

1. Launch Zanoza and tap **Import**.
2. Enter the delegated domain from your MasterDnsVPN server (the same value as the NS record, e.g. `v.example.com`).
3. Enter the shared encryption key (must match the server-side key).
4. Tap **Import**, then the connect (power) button.
5. The SOCKS5 proxy comes up at `127.0.0.1:41080`. Open Shadowrocket / Happ / Stash and add a SOCKS5 proxy pointing at that address.
6. Zanoza keeps the listener alive while you switch to the other app via a silent-audio background mode. Killing Zanoza from the app switcher stops the tunnel.

## How the background trick works

iOS suspends regular apps shortly after they leave the foreground. Zanoza declares `UIBackgroundModes = ["audio"]` and plays a 1-second silent PCM buffer on loop through `AVAudioEngine`. While audio is rendering, iOS keeps the process alive — and the SOCKS listener with it. The audio session uses `.mixWithOthers` so it does not interrupt your music. See `apple/Sources/ZanozaKit/Services/BackgroundRuntimeKeeper.swift`.

## Credits

- Upstream protocol and Go client: [MasterDnsVPN by MasterkinG32](https://github.com/masterking32/MasterDnsVPN)
- iOS application shell loosely follows the structure of [Godwit](https://github.com/plumbicon/godwit) (MIT)

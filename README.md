<div align="right">

**🇷🇺 Русский** · [🇬🇧 English](README.en.md)

</div>

# Zanoza

iOS-клиент для [MasterDnsVPN](https://github.com/masterking32/MasterDnsVPN) — VPN на основе туннелирования через DNS для сетей с жёсткой цензурой.

Приложение использует оригинальное ядро Go-клиента MasterDnsVPN, поднимает локальный SOCKS5-прокси на `127.0.0.1:41080` для подключения через сторонние VPN-приложения (Shadowrocket, Happ и т.п.), которые уже пропускают весь системный трафик через DNS-туннель.
Собственный VPN-профиль данное приложение **не** создаёт, поскольку оно не подписано в Apple Developer.
DNS-резолверы по умолчанию - от Яндекс.

## Структура репозитория

```
Zanoza/
├── apple/                            # Проект Xcode / SwiftPM
│   ├── Package.swift                 # Общая библиотека ZanozaKit
│   ├── project.yml                   # Описание проекта для XcodeGen
│   ├── Frameworks/                   # Сюда падает Mobile.xcframework
│   ├── Scripts/
│   │   ├── build-xcframework.sh         # gomobile bind → Mobile.xcframework
│   │   ├── build-ios-unsigned-local-ipa.sh
│   │   ├── prepare-xcode.sh             # обёртка над xcodegen
│   │   └── generate-icon.py             # генератор AppIcon (Pillow)
│   ├── Sources/
│   │   ├── ZanozaApp/                # таргет iOS-приложения
│   │   │   ├── Assets.xcassets/AppIcon.appiconset/
│   │   │   ├── Info.plist            # UIBackgroundModes=[audio]
│   │   │   └── ZanozaApp.swift
│   │   └── ZanozaKit/                # Общая SwiftPM-библиотека
│   │       ├── Models/               # ConnectionProfile, ClientStatus
│   │       ├── Services/             # MasterDnsEngine, BackgroundRuntimeKeeper, …
│   │       ├── ViewModels/           # ClientViewModel
│   │       ├── Views/                # ContentView, ImportProfileSheet, …
│   │       └── Resources/{en,ru}.lproj/Localizable.strings
│   └── Tests/ZanozaKitTests/
└── masterdns/                        # Vendored-форк MasterDnsVPN
    ├── go.mod                        # добавлена зависимость golang.org/x/mobile
    └── mobile/                       # gomobile-обёртка
        ├── mobile.go                 #   Start/Stop/IsRunning/SetLogWriter
        └── stdout_pump.go            #   перенаправляет stdout → LogWriter
```

## Для сборки

- macOS 14 + Xcode 16 (iOS-инструментарий идёт в составе Xcode)
- [Homebrew](https://brew.sh)
- `brew install go xcodegen`
- `go install golang.org/x/mobile/cmd/gomobile@latest && gomobile init`
- Python 3 с Pillow (`python3 -m pip install --user pillow`) — только если хотите пересобрать иконку приложения

## Сборка

```bash
# 1. Собираем Go-xcframework
apple/Scripts/build-xcframework.sh

# 2. Генерируем проект Xcode
apple/Scripts/prepare-xcode.sh

# 3. Собираем неподписанный IPA
apple/Scripts/build-ios-unsigned-local-ipa.sh
#   → apple/.build/ios-unsigned-local/Zanoza-unsigned.ipa
```

IPA-файл не подписан. Подпишите и установите его на устройство одним из способов:

- **[Sideloadly](https://sideloadly.io)** — перетащите IPA в окно, подпишите своим Apple ID и установите через USB.
- **AltStore / SideStore** — установка прямо на устройстве, после первой настройки Mac уже не нужен.

Перед первой установкой включите на iPhone **Настройки → Конфиденциальность и безопасность → Режим разработчика**.

## Использование

1. Запустите Zanoza и нажмите **Импорт**.
2. Введите делегированный домен с вашего сервера MasterDnsVPN (то же значение, что в NS-записи, например `v.example.com`).
3. Введите общий ключ шифрования (должен совпадать с ключом на стороне сервера).
4. Нажмите **Импорт**, затем кнопку питания. **Метод шифрования** должен совпадать со значением `DATA_ENCRYPTION_METHOD` в `server_config.toml` сервера (по умолчанию в обоих местах XOR).
5. SOCKS5-прокси поднимется на `127.0.0.1:41080`. Откройте Shadowrocket / Happ / и т.п., добавьте SOCKS5-прокси на этот адрес.
6. Zanoza держит туннель живым, даже когда приложение в фоне.

## Благодарности

- Протокол и ядро Go-клиента: [MasterDnsVPN от MasterkinG32](https://github.com/masterking32/MasterDnsVPN)
- UI iOS-приложения построен по структуре [Godwit](https://github.com/plumbicon/godwit) (MIT)

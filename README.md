<div align="right">

**🇷🇺 Русский** · [🇬🇧 English](README.en.md)

</div>

# Zanoza

iOS-клиент для [MasterDnsVPN](https://github.com/masterking32/MasterDnsVPN) — VPN на основе туннелирования через DNS для сетей с жёсткой цензурой.

Приложение оборачивает оригинальный Go-клиент MasterDnsVPN в iOS-приложение, поднимает локальный SOCKS5-прокси на `127.0.0.1:41080` и держит туннель активным, пока вы переключаетесь в другое приложение (Shadowrocket, Happ и т.п.), которое уже пропускает через этот прокси системный трафик.
Собственный VPN-профиль iOS приложение **не** создаёт, поскольку оно неподписанное.

## DNS-резолверы для работы в белых списках:

```
1. Яндекс (универсальные)
77.88.8.8
77.88.8.7
77.88.8.1
77.88.8.2
77.88.8.3
77.88.8.88
2. МТС: 
212.188.4.10
195.34.32.116
213.87.0.1
213.87.1.1
213.87.142.95
213.87.142.85
213.87.142.94
213.87.142.84
213.87.74.21
213.87.74.5
213.87.211.20
213.87.210.20
3. Мегафон, Yota:
84.201.166.221
10.10.22.3
83.169.217.22 
195.208.4.1
10.112.248.238
10.112.250.2
94.25.113.230
10.148.25.144
4. Билайн:
10.10.22.3
194.67.2.114
194.67.1.154
85.249.22.248
85.249.22.249
85.249.22.251
85.249.22.250
91.240.86.14
5. Теле2, Сбермобаил, Тинькофф:
176.59.31.182
176.59.31.183
176.59.223.159
176.59.95.243
176.59.63.148
176.59.63.204
176.59.127.156
176.59.62.125
176.59.62.126
```

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

## Что должно быть установлено

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

- **[Sideloadly](https://sideloadly.io)** — перетащите IPA в окно, подпишите своим Apple ID и установите через USB. Профили на бесплатном Apple ID действуют 7 дней; платный аккаунт Apple Developer (99 $ в год) даёт срок 1 год.
- **AltStore / SideStore** — установка прямо на устройстве, после первой настройки Mac уже не нужен.

Перед первой установкой включите на iPhone **Настройки → Конфиденциальность и безопасность → Режим разработчика**.

## Использование

1. Запустите Zanoza и нажмите **Импорт**.
2. Введите делегированный домен с вашего сервера MasterDnsVPN (то же значение, что в NS-записи, например `v.example.com`).
3. Введите общий ключ шифрования (должен совпадать с ключом на стороне сервера).
4. Нажмите **Импорт**, затем кнопку питания. **Метод шифрования** должен совпадать со значением `DATA_ENCRYPTION_METHOD` в `server_config.toml` сервера (по умолчанию в обоих местах XOR).
5. SOCKS5-прокси поднимется на `127.0.0.1:41080`. Откройте Shadowrocket / Happ / любой подобный — и добавьте SOCKS5-прокси на этот адрес.
6. Zanoza держит слушатель живым, пока вы переключаетесь между приложениями. Если выгнать Zanoza из переключателя приложений, туннель остановится.

## Благодарности

- Протокол и Go-клиент: [MasterDnsVPN от MasterkinG32](https://github.com/masterking32/MasterDnsVPN)
- Скелет iOS-приложения построен по структуре [Godwit](https://github.com/plumbicon/godwit) (MIT)

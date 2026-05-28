import SwiftUI

public struct SettingsView: View {
    @Binding var settings: AppSettings
    @ObservedObject var physicalInterfaceMonitor: PhysicalInterfaceMonitor
    let isTunnelRunning: Bool
    let onCommit: () -> Void

    public init(
        settings: Binding<AppSettings>,
        physicalInterfaceMonitor: PhysicalInterfaceMonitor,
        isTunnelRunning: Bool,
        onCommit: @escaping () -> Void
    ) {
        _settings = settings
        self.physicalInterfaceMonitor = physicalInterfaceMonitor
        self.isTunnelRunning = isTunnelRunning
        self.onCommit = onCommit
    }

    public var body: some View {
        Form {
            Section {
                SocksPortRow(value: $settings.socksPort)
                Toggle(AppLocalization.string("Require username/password"), isOn: $settings.socksAuthEnabled)
                if settings.socksAuthEnabled {
                    TextField(AppLocalization.string("Username"), text: $settings.socksUser)
                        .zanozaPlainInput()
                        .onSubmit(onCommit)
                    SecureField(AppLocalization.string("Password"), text: $settings.socksPass)
                        .zanozaPlainInput()
                        .onSubmit(onCommit)
                }
            } header: {
                Text(AppLocalization.string("SOCKS5 proxy"))
            } footer: {
                if isTunnelRunning {
                    Text(AppLocalization.string("Changes apply after reconnecting."))
                        .foregroundStyle(.orange)
                }
            }

            Section {
                Toggle(AppLocalization.string("Route system traffic through VPN"), isOn: $settings.systemVPNEnabled)
            } header: {
                Text(AppLocalization.string("VPN profile"))
            } footer: {
                Text(AppLocalization.string("Apple-signed builds only. Enabling the VPN profile on an unsigned build will require a reinstall."))
                    .foregroundColor(.orange)
            }

            Section {
                ResolverProviderPicker(
                    selection: $settings.resolverProviderID,
                    isDisabled: settings.useFastResolvers
                )
            } header: {
                Text(AppLocalization.string("DNS resolvers"))
            }

            Section {
                Toggle(AppLocalization.string("Use speed-unrestricted servers"), isOn: $settings.useFastResolvers)
            } footer: {
                Text(AppLocalization.string("Connection may be unstable! Do not use when mobile network restrictions apply!"))
                    .foregroundColor(.orange)
            }

            Section {
                ResolversTextEditor(text: $settings.customResolvers)
            } footer: {
                Text(AppLocalization.string("One resolver per line. Manual entries override the selected provider or speed-unrestricted servers. Leave empty to use the selected remote list."))
            }

            Section {
                HStack {
                    Text(AppLocalization.string("Version"))
                    Spacer()
                    Text(appVersionDisplay)
                        .foregroundColor(.secondary)
                        .font(.callout.monospacedDigit())
                        .textSelection(.enabled)
                }
                HStack {
                    Text(AppLocalization.string("Bound interface"))
                    Spacer()
                    Text(diagnosticDisplay)
                        .foregroundColor(.secondary)
                        .font(.callout.monospacedDigit())
                }
                if !physicalInterfaceMonitor.snapshot.ipv4.isEmpty {
                    HStack {
                        Text(AppLocalization.string("Source IPv4"))
                        Spacer()
                        Text(physicalInterfaceMonitor.snapshot.ipv4)
                            .foregroundColor(.secondary)
                            .font(.callout.monospacedDigit())
                            .textSelection(.enabled)
                    }
                }
                if !physicalInterfaceMonitor.snapshot.ipv6.isEmpty {
                    HStack {
                        Text(AppLocalization.string("Source IPv6"))
                        Spacer()
                        Text(physicalInterfaceMonitor.snapshot.ipv6)
                            .foregroundColor(.secondary)
                            .font(.callout.monospacedDigit())
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                }
                HStack {
                    Text(AppLocalization.string("Third-party VPN"))
                    Spacer()
                    Text(physicalInterfaceMonitor.snapshot.foreignVPNActive
                         ? AppLocalization.string("Active")
                         : AppLocalization.string("Not detected"))
                        .foregroundColor(physicalInterfaceMonitor.snapshot.foreignVPNActive ? .orange : .secondary)
                        .font(.callout.weight(.medium))
                }
            } header: {
                Text(AppLocalization.string("Diagnostics"))
            } footer: {
                diagnosticFooter
            }
        }
        .formStyle(.grouped)
        .onDisappear(perform: onCommit)
    }

    private var appVersionDisplay: String {
        let info = Bundle.main.infoDictionary
        let marketing = info?["CFBundleShortVersionString"] as? String
        let build = info?["CFBundleVersion"] as? String
        switch (marketing, build) {
        case let (m?, b?) where !m.isEmpty && !b.isEmpty:
            return "\(m) (\(b))"
        case let (m?, _) where !m.isEmpty:
            return m
        case let (_, b?) where !b.isEmpty:
            return "build \(b)"
        default:
            return "—"
        }
    }

    private var diagnosticDisplay: String {
        let snapshot = physicalInterfaceMonitor.snapshot
        if snapshot.name.isEmpty {
            return AppLocalization.string("None")
        }
        let typeLabel: String
        switch snapshot.type {
        case .wifi: typeLabel = AppLocalization.string("Wi-Fi")
        case .cellular: typeLabel = AppLocalization.string("Cellular")
        case .wired: typeLabel = AppLocalization.string("Wired")
        case .other, .none: typeLabel = AppLocalization.string("Other")
        }
        return "\(typeLabel) (\(snapshot.name))"
    }

    @ViewBuilder
    private var diagnosticFooter: some View {
        let snapshot = physicalInterfaceMonitor.snapshot
        if snapshot.name.isEmpty {
            Text(AppLocalization.string("Outbound traffic may loop through another active VPN app. Disable other VPN apps or restart Zanoza after Wi-Fi/cellular is up."))
                .foregroundColor(.orange)
        } else if snapshot.foreignVPNActive {
            Text(AppLocalization.string("Another VPN app is active. Zanoza pins its outbound DNS to this interface AND its source IP to bypass it. If the tunnel still stalls, check the other app for a 'Strict / Lockdown / Include All Networks' toggle and disable it."))
                .foregroundColor(.orange)
        } else {
            Text(AppLocalization.string("Outbound DNS queries are pinned to this physical interface, bypassing any other active VPN."))
        }
    }
}

private struct ResolverProviderPicker: View {
    @Binding var selection: String
    let isDisabled: Bool

    var body: some View {
        Picker(AppLocalization.string("Provider selection"), selection: normalizedSelection) {
            Text(AppLocalization.string("No provider"))
                .tag(AppSettings.noResolverProviderID)
            ForEach(ResolverCatalog.providers) { provider in
                Text(provider.displayName)
                    .tag(provider.id)
            }
        }
        .disabled(isDisabled)
    }

    private var normalizedSelection: Binding<String> {
        Binding(
            get: { AppSettings.normalizedResolverProviderID(selection) },
            set: { selection = AppSettings.normalizedResolverProviderID($0) }
        )
    }
}

private struct SocksPortRow: View {
    @Binding var value: Int
    @FocusState private var isFocused: Bool
    @State private var text: String = ""

    var body: some View {
        HStack {
            Text(AppLocalization.string("SOCKS port"))
            Spacer(minLength: 12)
            TextField("", text: textBinding)
                .multilineTextAlignment(.trailing)
                .focused($isFocused)
                .frame(width: 92)
                #if os(iOS)
                .keyboardType(.numberPad)
                .textFieldStyle(.plain)
                #else
                .textFieldStyle(.plain)
                #endif
            Stepper("", value: clampedValue, in: AppSettings.socksPortRange)
                .labelsHidden()
                .fixedSize()
        }
        .onAppear { text = "\(value)" }
        .onChange(of: value) { newValue in
            if !isFocused { text = "\(newValue)" }
        }
        .onChange(of: isFocused) { focused in
            if !focused { commit() }
        }
    }

    private var textBinding: Binding<String> {
        Binding(
            get: { text.isEmpty && !isFocused ? "\(value)" : text },
            set: { text = $0.filter(\.isNumber) }
        )
    }

    private var clampedValue: Binding<Int> {
        Binding(
            get: { value },
            set: { newValue in
                let clamped = AppSettings.clampedSocksPort(newValue)
                value = clamped
                text = "\(clamped)"
            }
        )
    }

    private func commit() {
        let digits = text.filter(\.isNumber)
        if let parsed = Int(digits) {
            value = AppSettings.clampedSocksPort(parsed)
        }
        text = "\(value)"
    }
}

private struct ResolversTextEditor: View {
    @Binding var text: String

    var body: some View {
        #if os(iOS)
        TextEditor(text: $text)
            .font(.system(.footnote, design: .monospaced))
            .frame(minHeight: 140)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
        #else
        TextEditor(text: $text)
            .font(.system(.footnote, design: .monospaced))
            .frame(minHeight: 140)
        #endif
    }
}

import SwiftUI

public struct ProfileEditorView: View {
    @Binding var profile: ConnectionProfile
    let validationMessage: String?
    let onCommit: () -> Void

    public init(
        profile: Binding<ConnectionProfile>,
        validationMessage: String?,
        onCommit: @escaping () -> Void
    ) {
        _profile = profile
        self.validationMessage = validationMessage
        self.onCommit = onCommit
    }

    public var body: some View {
        Form {
            if let validationMessage {
                Section {
                    Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }

            Section(AppLocalization.string("Profile")) {
                TextField(AppLocalization.string("Profile name"), text: $profile.name)
                    .zanozaPlainInput()
                    .onSubmit(onCommit)
            }

            Section(AppLocalization.string("Server")) {
                TextField("v.example.com", text: $profile.domain)
                    .zanozaPlainInput()
                    .onSubmit(onCommit)
                SecureField(AppLocalization.string("Encryption key"), text: $profile.encryptionKey)
                    .zanozaPlainInput()
                    .onSubmit(onCommit)
                Picker(AppLocalization.string("Encryption method"), selection: $profile.encryptionMethod) {
                    ForEach(EncryptionMethod.allCases) { method in
                        Text(method.title).tag(method)
                    }
                }
            }

            Section(AppLocalization.string("Local SOCKS5")) {
                StepperPortRow(value: $profile.socksPort)
                Toggle(AppLocalization.string("Require username/password"), isOn: $profile.socksAuthEnabled)
                if profile.socksAuthEnabled {
                    TextField(AppLocalization.string("Username"), text: $profile.socksUser)
                        .zanozaPlainInput()
                        .onSubmit(onCommit)
                    SecureField(AppLocalization.string("Password"), text: $profile.socksPass)
                        .zanozaPlainInput()
                        .onSubmit(onCommit)
                }
            }

            Section(AppLocalization.string("Reliability")) {
                Picker(AppLocalization.string("Resolver strategy"), selection: $profile.resolverBalancingStrategy) {
                    ForEach(BalancingStrategy.allCases) { strategy in
                        Text(strategy.title).tag(strategy)
                    }
                }
                Stepper(
                    AppLocalization.format("Packet duplication: %d", profile.packetDuplicationCount),
                    value: $profile.packetDuplicationCount,
                    in: 1...10
                )
                Stepper(
                    AppLocalization.format("Setup duplication: %d", profile.setupPacketDuplicationCount),
                    value: $profile.setupPacketDuplicationCount,
                    in: profile.packetDuplicationCount...12
                )
            }

            Section(AppLocalization.string("Compression")) {
                Picker(AppLocalization.string("Upload"), selection: $profile.uploadCompression) {
                    ForEach(CompressionType.allCases) { type in
                        Text(type.title).tag(type)
                    }
                }
                Picker(AppLocalization.string("Download"), selection: $profile.downloadCompression) {
                    ForEach(CompressionType.allCases) { type in
                        Text(type.title).tag(type)
                    }
                }
            }

            Section(AppLocalization.string("Logging")) {
                Picker(AppLocalization.string("Log level"), selection: $profile.logLevel) {
                    ForEach(LogLevel.allCases) { level in
                        Text(level.title).tag(level)
                    }
                }
            }

            Section(AppLocalization.string("Resolvers (optional)")) {
                ResolversTextEditor(text: $profile.customResolvers)
                Text(AppLocalization.string("Leave empty to use the bundled list of public resolvers."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onDisappear(perform: onCommit)
    }
}

private struct StepperPortRow: View {
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
            Stepper("", value: clampedValue, in: ConnectionProfile.socksPortRange)
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
                let clamped = ConnectionProfile.clampedSocksPort(newValue)
                value = clamped
                text = "\(clamped)"
            }
        )
    }

    private func commit() {
        let digits = text.filter(\.isNumber)
        if let parsed = Int(digits) {
            value = ConnectionProfile.clampedSocksPort(parsed)
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
            .frame(minHeight: 120)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
        #else
        TextEditor(text: $text)
            .font(.system(.footnote, design: .monospaced))
            .frame(minHeight: 120)
        #endif
    }
}

extension View {
    @ViewBuilder
    func zanozaPlainInput() -> some View {
        #if os(iOS)
        self
            .textFieldStyle(.plain)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        #else
        self
            .textFieldStyle(.plain)
        #endif
    }
}

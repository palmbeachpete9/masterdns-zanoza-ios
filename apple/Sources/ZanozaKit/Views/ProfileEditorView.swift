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

            Section(AppLocalization.string("Profile name")) {
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

            Section(AppLocalization.string("Reliability")) {
                Picker(AppLocalization.string("Resolver strategy"), selection: $profile.resolverBalancingStrategy) {
                    ForEach(BalancingStrategy.allCases) { strategy in
                        Text(strategy.title).tag(strategy)
                    }
                }
                Stepper(
                    "\(AppLocalization.string("Packet duplication")): \(profile.packetDuplicationCount)",
                    value: $profile.packetDuplicationCount,
                    in: 1...10
                )
                Stepper(
                    "\(AppLocalization.string("Setup duplication")): \(profile.setupPacketDuplicationCount)",
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
        }
        .formStyle(.grouped)
        .onDisappear(perform: onCommit)
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

import SwiftUI

public struct ImportProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var domain: String = ""
    @State private var encryptionKey: String = ""
    @State private var name: String = ""

    let isImporting: Bool
    let onImport: (_ domain: String, _ encryptionKey: String, _ name: String?) -> Void

    public init(
        isImporting: Bool,
        onImport: @escaping (_ domain: String, _ encryptionKey: String, _ name: String?) -> Void
    ) {
        self.isImporting = isImporting
        self.onImport = onImport
    }

    private var trimmedDomain: String {
        domain.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedKey: String {
        encryptionKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canImport: Bool {
        !trimmedDomain.isEmpty &&
            trimmedDomain.contains(".") &&
            !trimmedKey.isEmpty &&
            !isImporting
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("v.example.com", text: $domain)
                        .zanozaPlainInput()
                        .onSubmit(importIfReady)
                } header: {
                    Text(AppLocalization.string("Delegated domain"))
                } footer: {
                    Text(AppLocalization.string("During installation, you were asked for a domain. It must be the same delegated subdomain you configured in the NS record, for example v.example.com."))
                }

                Section {
                    SecureField(AppLocalization.string("Encryption key"), text: $encryptionKey)
                        .zanozaPlainInput()
                        .onSubmit(importIfReady)
                } header: {
                    Text(AppLocalization.string("Shared key"))
                } footer: {
                    Text(AppLocalization.string("Must match the key configured on the MasterDnsVPN server."))
                }

                Section {
                    TextField(AppLocalization.string("Optional"), text: $name)
                        .zanozaPlainInput()
                        .onSubmit(importIfReady)
                } header: {
                    Text(AppLocalization.string("Profile name"))
                }
            }
            .formStyle(.grouped)
            .navigationTitle(AppLocalization.string("Import profile"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.string("Cancel"), role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: importIfReady) {
                        ImportLabel(isImporting: isImporting)
                    }
                    .disabled(!canImport)
                }
            }
        }
        #if os(macOS)
        .frame(width: 460, height: 380)
        #endif
    }

    private func importIfReady() {
        guard canImport else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        onImport(trimmedDomain, trimmedKey, trimmedName.isEmpty ? nil : trimmedName)
    }
}

public struct ImportProfileLinkSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var sharingLink: String
    @State private var importError: String?

    let isImporting: Bool
    let onImport: (_ link: String) -> String?

    public init(
        isImporting: Bool,
        onImport: @escaping (_ link: String) -> String?
    ) {
        _sharingLink = State(initialValue: ClipboardService.string ?? "")
        self.isImporting = isImporting
        self.onImport = onImport
    }

    private var trimmedLink: String {
        sharingLink.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canImport: Bool {
        !trimmedLink.isEmpty && !isImporting
    }

    public var body: some View {
        NavigationStack {
            Form {
                if let importError {
                    Section {
                        Label(importError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    TextEditor(text: $sharingLink)
                        .font(.callout.monospaced())
                        .frame(minHeight: 112)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        #endif
                } header: {
                    Text(AppLocalization.string("Profile sharing link"))
                } footer: {
                    Text(AppLocalization.string("Paste a Zanoza profile sharing link."))
                }
            }
            .formStyle(.grouped)
            .navigationTitle(AppLocalization.string("Import profile"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.string("Cancel"), role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: importIfReady) {
                        ImportLabel(isImporting: isImporting)
                    }
                    .disabled(!canImport)
                }
            }
        }
        #if os(macOS)
        .frame(width: 460, height: 280)
        #endif
    }

    private func importIfReady() {
        guard canImport else { return }
        if let message = onImport(trimmedLink) {
            importError = message
        } else {
            dismiss()
        }
    }
}

private struct ImportLabel: View {
    let isImporting: Bool

    var body: some View {
        if isImporting {
            Label(AppLocalization.string("Importing..."), systemImage: "arrow.triangle.2.circlepath")
        } else {
            Label(AppLocalization.string("Import"), systemImage: "square.and.arrow.down")
        }
    }
}

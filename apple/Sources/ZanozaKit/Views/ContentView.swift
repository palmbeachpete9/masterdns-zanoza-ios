import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

public struct ContentView: View {
    @StateObject private var viewModel: ClientViewModel
    @State private var isShowingImporter = false
    @State private var isShowingLinkImporter = false
    @State private var isShowingLogs = false
    @State private var isShowingSettings = false
    @State private var detailDestination: DetailDestination?

    @MainActor
    public init() {
        _viewModel = StateObject(wrappedValue: ClientViewModel())
    }

    @MainActor
    public init(viewModel: ClientViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        NavigationStack {
            Group {
                if viewModel.profiles.isEmpty {
                    EmptyProfilesView(onImport: { isShowingImporter = true })
                } else {
                    ProfilesHomeView(
                        viewModel: viewModel,
                        onShowProfileDetails: showProfileDetails
                    )
                }
            }
            .navigationTitle("Zanoza")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Label(AppLocalization.string("Settings"), systemImage: "gearshape")
                    }
                    Button {
                        isShowingLogs = true
                    } label: {
                        Label(AppLocalization.string("Logs"), systemImage: "list.bullet.rectangle")
                    }
                }
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        isShowingImporter = true
                    } label: {
                        Label(AppLocalization.string("Import"), systemImage: "square.and.arrow.down")
                    }
                    Button {
                        isShowingLinkImporter = true
                    } label: {
                        Label(AppLocalization.string("Import from clipboard"), systemImage: "doc.on.clipboard")
                    }
                }
                #else
                ToolbarItemGroup(placement: .navigation) {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Label(AppLocalization.string("Settings"), systemImage: "gearshape")
                    }
                    Button {
                        isShowingLogs = true
                    } label: {
                        Label(AppLocalization.string("Logs"), systemImage: "list.bullet.rectangle")
                    }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        isShowingImporter = true
                    } label: {
                        Label(AppLocalization.string("Import"), systemImage: "square.and.arrow.down")
                    }
                    Button {
                        isShowingLinkImporter = true
                    } label: {
                        Label(AppLocalization.string("Import from clipboard"), systemImage: "doc.on.clipboard")
                    }
                }
                #endif
            }
        }
        .sheet(isPresented: $isShowingImporter) {
            ImportProfileSheet(isImporting: viewModel.isImporting) { domain, key, name in
                viewModel.importProfile(domain: domain, encryptionKey: key, name: name)
                isShowingImporter = false
            }
        }
        .sheet(isPresented: $isShowingLinkImporter) {
            ImportProfileLinkSheet(isImporting: viewModel.isImporting) { link in
                if viewModel.importSharedProfile(link) { return nil }
                return viewModel.importErrorMessage ?? AppLocalization.string("Invalid profile sharing link.")
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            NavigationStack {
                SettingsView(
                    settings: $viewModel.settings,
                    physicalInterfaceMonitor: viewModel.physicalInterfaceMonitor,
                    isTunnelRunning: viewModel.status.isRunning,
                    onCommit: viewModel.saveSettings
                )
                .navigationTitle(AppLocalization.string("Settings"))
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(AppLocalization.string("Done")) {
                            viewModel.saveSettings()
                            isShowingSettings = false
                        }
                    }
                }
            }
            #if os(macOS)
            .frame(width: 480, height: 520)
            #endif
        }
        .sheet(item: $detailDestination) { destination in
            detailView(for: destination)
        }
        .logPresentation(isPresented: $isShowingLogs) {
            LogScreen(logs: viewModel.logs) { viewModel.clearLogs() }
        }
        .overlay(alignment: .top) {
            if let message = viewModel.importErrorMessage {
                ImportErrorBanner(message: message) { viewModel.clearImportError() }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        #if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)) { _ in
            viewModel.shutdownForAppTermination()
        }
        #elseif os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            viewModel.shutdownForAppTermination()
        }
        #endif
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: viewModel.importErrorMessage)
    }

    private func showProfileDetails(_ profile: ConnectionProfile) {
        viewModel.selectProfile(profile.id)
        detailDestination = .profile(profile.id)
    }

    @ViewBuilder
    private func detailView(for destination: DetailDestination) -> some View {
        NavigationStack {
            switch destination {
            case .profile:
                ProfileDetailScreen(viewModel: viewModel)
            }
        }
    }
}

private enum DetailDestination: Identifiable {
    case profile(UUID)
    var id: String {
        switch self { case .profile(let id): "profile-\(id.uuidString)" }
    }
}

private struct ProfileDetailScreen: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ClientViewModel

    var body: some View {
        ProfileEditorView(
            profile: $viewModel.draft,
            validationMessage: viewModel.validationMessage,
            onCommit: viewModel.saveDraft
        )
        .navigationTitle(viewModel.selectedProfileName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(AppLocalization.string("Done")) {
                    viewModel.saveDraft()
                    dismiss()
                }
            }
        }
    }
}

private struct ProfilesHomeView: View {
    @ObservedObject var viewModel: ClientViewModel
    let onShowProfileDetails: (ConnectionProfile) -> Void

    var body: some View {
        List {
            ConnectionPanel(viewModel: viewModel)
                .listRowSeparator(.hidden, edges: .bottom)
                #if os(iOS)
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                #endif

            Section(AppLocalization.string("Profiles")) {
                ForEach(viewModel.profiles) { profile in
                    ProfileRow(
                        profile: profile,
                        isSelected: viewModel.selectedProfileID == profile.id,
                        isPinging: viewModel.pingingProfileIDs.contains(profile.id),
                        pingState: viewModel.pingResults[profile.id],
                        onSelect: { viewModel.selectProfile(profile.id) },
                        onPing: { viewModel.pingProfile(profile.id) },
                        onInfo: { onShowProfileDetails(profile) }
                    )
                    .swipeActions {
                        Button(AppLocalization.string("Delete"), role: .destructive) {
                            viewModel.deleteProfiles(ids: [profile.id])
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        if viewModel.selectedProfileID == profile.id {
                            Button {
                                viewModel.shareProfile(profile)
                            } label: {
                                Label(AppLocalization.string("Share"), systemImage: "square.and.arrow.up")
                            }
                            .tint(.green)
                        }
                    }
                }
                .onDelete { offsets in
                    let ids = offsets.compactMap { idx in
                        viewModel.profiles.indices.contains(idx) ? viewModel.profiles[idx].id : nil
                    }
                    viewModel.deleteProfiles(ids: ids)
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
    }
}

private struct ConnectionPanel: View {
    @ObservedObject var viewModel: ClientViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    StatusBadge(status: viewModel.status)
                    if viewModel.selectedProfileID != nil {
                        Text(detailLine)
                            .font(.callout.weight(.medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    if let port = viewModel.activeSocksPort, viewModel.status == .ready {
                        // Direct String interpolation avoids the Russian
                        // locale's NBSP thousand grouping that `%d` produces.
                        Text("SOCKS5 127.0.0.1:\(String(port))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.green)
                    }
                }
                .layoutPriority(1)
                Spacer(minLength: 8)
                connectionButton
            }

            if let validationMessage = viewModel.validationMessage, viewModel.selectedProfileID != nil {
                Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private var connectionButton: some View {
        if viewModel.status.isRunning {
            Button(action: viewModel.stop) {
                Image(systemName: "power")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 36, height: 30)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .accessibilityLabel(AppLocalization.string("Disconnect"))
            .disabled(viewModel.status == .stopping)
        } else {
            Button(action: viewModel.start) {
                Image(systemName: "power")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 36, height: 30)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .accessibilityLabel(AppLocalization.string("Connect"))
            .disabled(!viewModel.canStart)
        }
    }

    private var detailLine: String {
        [viewModel.selectedProfileName, viewModel.draft.domain]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

private struct ProfileRow: View {
    let profile: ConnectionProfile
    let isSelected: Bool
    let isPinging: Bool
    let pingState: ProfilePingResult?
    let onSelect: () -> Void
    let onPing: () -> Void
    let onInfo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onSelect) {
                HStack(spacing: 12) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "network")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                        .frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(profile.displayName)
                            .font(.body.weight(.medium))
                            .lineLimit(1)
                        Text(profile.listDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .layoutPriority(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 4) {
                PingStateLabel(state: pingState, isPinging: isPinging)
                PingButton(isPinging: isPinging, action: onPing)
                InfoButton(action: onInfo)
            }
        }
    }
}

private struct PingButton: View {
    let isPinging: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "speedometer")
                .font(.system(size: 17, weight: .medium))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .opacity(isPinging ? 0.45 : 1)
        .disabled(isPinging)
        .accessibilityLabel(AppLocalization.string("Ping profile"))
    }
}

private struct InfoButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "info.circle")
                .font(.system(size: 18, weight: .medium))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityLabel(AppLocalization.string("Details"))
    }
}

private struct PingStateLabel: View {
    let state: ProfilePingResult?
    let isPinging: Bool

    var body: some View {
        Group {
            if isPinging {
                ProgressView().controlSize(.small)
            } else if let state {
                switch state {
                case .success(let ms):
                    Text("\(String(ms)) \(AppLocalization.string("ms"))")
                        .foregroundStyle(color(for: ms))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .help(AppLocalization.string("Last ping (ms)."))
                case .failure(let message):
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                        .help(message)
                }
            } else {
                Color.clear
            }
        }
        .font(.caption.weight(.semibold))
        .frame(width: width, height: 30, alignment: alignment)
    }

    private var width: CGFloat {
        if isPinging { return 30 }
        switch state {
        case .success: return 60
        case .failure: return 30
        case .none: return 30
        }
    }

    private var alignment: Alignment {
        width == 30 ? .center : .trailing
    }

    private func color(for ms: Int) -> Color {
        if ms < 150 { return .green }
        if ms < 350 { return .orange }
        return .red
    }
}

private struct EmptyProfilesView: View {
    let onImport: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 32)
            Image(systemName: "globe.badge.chevron.backward")
                .font(.system(size: 46, weight: .regular))
                .foregroundStyle(.secondary)
            VStack(spacing: 6) {
                Text(AppLocalization.string("No profiles yet"))
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(AppLocalization.string("Tap Import to add a Zanoza server using its delegated domain and encryption key."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button(action: onImport) {
                Label(AppLocalization.string("Import"), systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Spacer(minLength: 32)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ImportErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout.weight(.medium))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppLocalization.string("Dismiss"))
        }
        .padding(.vertical, 12)
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 16, x: 0, y: 8)
    }
}

private struct StatusBadge: View {
    let status: ClientStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        switch status {
        case .failed(let message):
            return message.isEmpty
                ? AppLocalization.string("Error")
                : AppLocalization.format("Error: %@", message)
        default:
            return status.title
        }
    }

    private var color: Color {
        switch status {
        case .stopped: .secondary
        case .starting, .stopping: .orange
        case .ready: .green
        case .failed: .red
        }
    }
}

private struct LogScreen: View {
    @Environment(\.dismiss) private var dismiss
    let logs: [String]
    let onClear: () -> Void

    var body: some View {
        NavigationStack {
            LogView(logs: logs, onClear: onClear)
                .navigationTitle(AppLocalization.string("Logs"))
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(AppLocalization.string("Done")) { dismiss() }
                    }
                }
        }
        #if os(macOS)
        .frame(width: 460, height: 500)
        #endif
    }
}

private extension View {
    @ViewBuilder
    func logPresentation<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        #if os(iOS)
        self.fullScreenCover(isPresented: isPresented, content: content)
        #else
        self.sheet(isPresented: isPresented, content: content)
        #endif
    }
}

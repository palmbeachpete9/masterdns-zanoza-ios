import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

public struct LogView: View {
    let logs: [String]
    let onClear: () -> Void

    public init(logs: [String], onClear: @escaping () -> Void) {
        self.logs = logs
        self.onClear = onClear
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(AppLocalization.string("Logs"), systemImage: "list.bullet.rectangle")
                    #if os(iOS)
                    .font(.subheadline.weight(.semibold))
                    #else
                    .font(.headline)
                    #endif
                Spacer()
                Button(action: copyLogs) {
                    Label(AppLocalization.string("Copy"), systemImage: "doc.on.doc")
                }
                .disabled(logs.isEmpty)
                Button(action: onClear) {
                    Label(AppLocalization.string("Clear"), systemImage: "trash")
                }
                .disabled(logs.isEmpty)
            }
            .padding([.horizontal, .top])

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        if logs.isEmpty {
                            Text(AppLocalization.string("No log lines yet."))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 8)
                        } else {
                            ForEach(Array(logs.enumerated()), id: \.offset) { index, line in
                                Text(line)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                                    .id(index)
                            }
                        }
                    }
                    .padding()
                }
                .onChange(of: logs.count) { count in
                    guard count > 0 else { return }
                    proxy.scrollTo(count - 1, anchor: .bottom)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(iOS)
        .font(.subheadline)
        #endif
    }

    private func copyLogs() {
        let text = logs.joined(separator: "\n")
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}

import AppKit
import SwiftUI
import LerroCore

struct PrivacySettingsTab: View {
    @Bindable var session: AppSession
    @State private var pendingRetention: HistoryRetention?
    @State private var showRetentionConfirmation = false
    @State private var showDeleteAllConfirmation = false

    var body: some View {
        Form {
            Section {
                Picker("保存历史", selection: retentionSelection) {
                    Text("永久").tag(HistoryRetention.forever)
                    Text("1 个月").tag(HistoryRetention.oneMonth)
                    Text("1 周").tag(HistoryRetention.oneWeek)
                    Text("24 小时").tag(HistoryRetention.oneDay)
                    Text("永不").tag(HistoryRetention.never)
                }

                Toggle("保存原始录音", isOn: $session.preferences.saveAudio)
                    .disabled(session.preferences.historyRetention == .never)
            }

            Section {
                LabeledContent("数据位置") {
                    HStack(spacing: 8) {
                        Text("这台 Mac")
                            .foregroundStyle(LerroTheme.secondaryText)
                        Button("在 Finder 中显示", action: revealDataDirectory)
                            .buttonStyle(LerroButtonStyle(.secondary))
                            .disabled(dataDirectory == nil)
                    }
                }
            }

            Section {
                Button("删除全部历史和录音…", role: .destructive) {
                    showDeleteAllConfirmation = true
                }
                .buttonStyle(.plain)
                .foregroundStyle(LerroTheme.danger)
            }
        }
        .settingsForm(height: 320)
        .confirmationDialog(
            "更改保存时长",
            isPresented: $showRetentionConfirmation,
            titleVisibility: .visible
        ) {
            Button(LocalizedStringKey(pendingRetention == .never ? "关闭保存" : "确认更改")) {
                if let pendingRetention {
                    session.setHistoryRetention(pendingRetention)
                }
                pendingRetention = nil
            }
            Button("取消", role: .cancel) { pendingRetention = nil }
        } message: {
            Text(LocalizedStringKey(retentionConfirmationMessage))
        }
        .confirmationDialog(
            "删除全部历史和录音？",
            isPresented: $showDeleteAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) { session.deleteAllHistory() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这台 Mac 上的全部历史记录和录音会被永久删除，无法恢复。")
        }
    }

    /// Lengthening applies immediately. Shortening asks first because older
    /// records are cleaned up under the new retention.
    private var retentionSelection: Binding<HistoryRetention> {
        Binding {
            session.preferences.historyRetention
        } set: { selected in
            let current = session.preferences.historyRetention
            guard selected != current else { return }
            if selected.duration < current.duration {
                pendingRetention = selected
                showRetentionConfirmation = true
            } else {
                session.setHistoryRetention(selected)
            }
        }
    }

    private var retentionConfirmationMessage: String {
        pendingRetention == .never
            ? "新的记录将不再保存；已有记录可在历史页单独删除。"
            : "超过所选时长的记录会根据本地保留策略清理。"
    }

    // MARK: Data location

    /// Nil in fixture mode, which keeps the real data directory out of reach.
    private var dataDirectory: URL? {
        guard ProcessInfo.processInfo.environment["LERRO_FIXTURE_MODE"] != "1" else { return nil }
        return ApplicationPaths.live().rootDirectory
    }

    private func revealDataDirectory() {
        guard let dataDirectory,
              FileManager.default.fileExists(atPath: dataDirectory.path) else { return }
        NSWorkspace.shared.open(dataDirectory)
    }
}

private extension HistoryRetention {
    /// Ordering used to tell shortening from lengthening.
    var duration: Int {
        switch self {
        case .never: 0
        case .oneDay: 1
        case .oneWeek: 2
        case .oneMonth: 3
        case .forever: 4
        }
    }
}

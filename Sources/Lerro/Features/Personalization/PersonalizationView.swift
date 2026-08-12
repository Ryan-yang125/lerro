import AppKit
import SwiftUI
import LerroCore

struct PersonalizationView: View {
    @Bindable var session: AppSession
    @State private var editingProfile: AppToneProfile?
    @State private var selectedApplication: ApplicationDescriptor?
    @State private var isApplicationPickerPresented = false
    @State private var isEditorPresented = false
    @Environment(\.locale) private var locale

    private let columns = [
        GridItem(.adaptive(minimum: 220, maximum: 300), spacing: 14, alignment: .top)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                LerroPageTitle(title: localized("个性化"))
                    .frame(height: 40)
                Spacer()
                if aiIsReady {
                    Button("新增应用", systemImage: "plus") {
                        beginAddingApplication()
                    }
                    .buttonStyle(LerroPillButtonStyle(prominent: true))
                } else {
                    Button("启用 AI", systemImage: "sparkles") {
                        session.presentSettings(SettingsDestination.intelligence)
                    }
                    .buttonStyle(LerroPillButtonStyle(prominent: true))
                }
            }

            ScrollView {
                if aiIsReady {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                        ForEach(session.preferences.appToneProfiles) { profile in
                            AppToneCard(
                                profile: profile,
                                iconData: descriptor(for: profile.bundleIdentifier)?.iconData,
                                edit: { edit(profile) },
                                toggle: { enabled in
                                    var updated = profile
                                    updated.enabled = enabled
                                    session.saveAppToneProfile(updated)
                                },
                                delete: { session.deleteAppToneProfile(profile) }
                            )
                        }

                        Button(action: beginAddingApplication) {
                            VStack(spacing: 10) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 24, weight: .medium))
                                Text("新增应用")
                                    .font(LerroTheme.font(14, weight: .medium))
                            }
                            .foregroundStyle(LerroTheme.accent)
                            .frame(maxWidth: .infinity, minHeight: 150)
                            .background(LerroTheme.fillContainerThin)
                            .clipShape(RoundedRectangle(cornerRadius: LerroTheme.cardRadius, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: LerroTheme.cardRadius, style: .continuous)
                                    .stroke(LerroTheme.focusBorder.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [5]))
                            }
                        }
                        .buttonStyle(LerroPressButtonStyle())
                    }
                    .padding(.top, 18)
                    .padding(.trailing, 15)
                    .padding(.bottom, 24)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 30, weight: .medium))
                            .foregroundStyle(LerroTheme.accent)
                        Text("应用语气需要 AI")
                            .font(LerroTheme.font(14, weight: .medium))
                        Button("启用 AI") {
                            session.presentSettings(SettingsDestination.intelligence)
                        }
                            .buttonStyle(LerroPillButtonStyle(prominent: true))
                    }
                    .frame(maxWidth: .infinity, minHeight: 360)
                }
            }
        }
        .padding(.top, LerroTheme.contentTopPadding)
        .padding(.horizontal, LerroTheme.contentHorizontalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LerroTheme.main)
        .task { session.refreshAvailableApplications() }
        .sheet(isPresented: $isApplicationPickerPresented) {
            ApplicationPickerSheet(
                applications: session.availableApplications,
                excludedBundleIdentifiers: Set(session.preferences.appToneProfiles.map(\.bundleIdentifier)),
                select: { application in
                    selectedApplication = application
                    isApplicationPickerPresented = false
                    isEditorPresented = true
                },
                cancel: { isApplicationPickerPresented = false }
            )
        }
        .sheet(isPresented: $isEditorPresented, onDismiss: resetEditor) {
            AppToneEditorSheet(
                session: session,
                application: selectedApplication,
                profile: editingProfile,
                save: { profile in
                    session.saveAppToneProfile(
                        profile,
                        replacingBundleIdentifier: editingProfile?.bundleIdentifier
                    )
                    isEditorPresented = false
                },
                cancel: { isEditorPresented = false }
            )
        }
    }

    private var aiIsReady: Bool {
        switch session.preferences.intelligenceMode {
        case .raw: false
        case .remote: session.preferences.remoteProvider.isReadyForUse
        case .local: session.localAIIsReady
        }
    }

    private func descriptor(for bundleIdentifier: String) -> ApplicationDescriptor? {
        session.availableApplications.first { $0.bundleIdentifier == bundleIdentifier }
    }

    private func beginAddingApplication() {
        editingProfile = nil
        selectedApplication = nil
        isApplicationPickerPresented = true
    }

    private func edit(_ profile: AppToneProfile) {
        editingProfile = profile
        selectedApplication = descriptor(for: profile.bundleIdentifier)
            ?? ApplicationDescriptor(
                bundleIdentifier: profile.bundleIdentifier,
                name: profile.applicationName,
                iconData: nil,
                isRunning: false
            )
        isEditorPresented = true
    }

    private func resetEditor() {
        editingProfile = nil
        selectedApplication = nil
    }

    private func localized(_ key: String) -> String {
        LerroInterfaceLocalization.string(key, locale: locale)
    }
}

private struct AppToneCard: View {
    let profile: AppToneProfile
    let iconData: Data?
    let edit: () -> Void
    let toggle: (Bool) -> Void
    let delete: () -> Void
    @State private var showDeleteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 11) {
                ApplicationIcon(data: iconData, name: profile.applicationName)
                Text(verbatim: profile.applicationName)
                    .font(LerroTheme.font(14, weight: .medium))
                    .lineLimit(1)
                Spacer()
                Toggle("启用", isOn: Binding(
                    get: { profile.enabled },
                    set: { enabled in toggle(enabled) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }

            Text(verbatim: profile.instruction)
                .font(LerroTheme.font(13))
                .foregroundStyle(LerroTheme.secondaryText)
                .lineLimit(3)
                .frame(maxWidth: .infinity, minHeight: 50, alignment: .topLeading)

            HStack {
                Text(verbatim: profile.bundleIdentifier)
                    .font(LerroTheme.font(12))
                    .foregroundStyle(LerroTheme.metadataText)
                    .lineLimit(1)
                Spacer()
                LerroIconButton(systemName: "pencil", help: "编辑", action: edit)
                LerroIconButton(systemName: "trash", help: "删除") {
                    showDeleteConfirmation = true
                }
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(LerroTheme.topLayer)
        .clipShape(RoundedRectangle(cornerRadius: LerroTheme.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: LerroTheme.cardRadius, style: .continuous)
                .stroke(LerroTheme.thinBorder)
        }
        .shadow(color: LerroTheme.cardShadow, radius: 2, x: 0, y: 1)
        .contextMenu {
            Button("编辑", action: edit)
            Button("删除", role: .destructive) { showDeleteConfirmation = true }
        }
        .alert("删除这个应用语气？", isPresented: $showDeleteConfirmation) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive, action: delete)
        }
    }
}

private struct ApplicationPickerSheet: View {
    let applications: [ApplicationDescriptor]
    let excludedBundleIdentifiers: Set<String>
    let select: (ApplicationDescriptor) -> Void
    let cancel: () -> Void
    @State private var searchText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("选择应用")
                    .lerroTypography(.title)
                Spacer()
                Button("取消", action: cancel)
                    .buttonStyle(LerroPillButtonStyle())
            }

            LerroSearchField(placeholder: "搜索已安装应用", text: $searchText)

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(filteredApplications) { application in
                        Button { select(application) } label: {
                            HStack(spacing: 12) {
                                ApplicationIcon(
                                    data: application.iconData,
                                    name: application.name
                                )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: application.name)
                                        .font(LerroTheme.font(14, weight: .medium))
                                    Text(verbatim: application.bundleIdentifier)
                                        .font(LerroTheme.font(12))
                                        .foregroundStyle(LerroTheme.metadataText)
                                }
                                Spacer()
                                if application.isRunning {
                                    Text("运行中")
                                        .font(LerroTheme.font(12, weight: .medium))
                                        .foregroundStyle(LerroTheme.green)
                                }
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(LerroTheme.tertiaryText)
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 56)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(LerroNavigationButtonStyle(selected: false))
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 520, height: 520)
        .background(LerroTheme.main)
    }

    private var filteredApplications: [ApplicationDescriptor] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return applications.filter { application in
            !excludedBundleIdentifiers.contains(application.bundleIdentifier)
                && (query.isEmpty
                    || application.name.localizedCaseInsensitiveContains(query)
                    || application.bundleIdentifier.localizedCaseInsensitiveContains(query))
        }
    }
}

private struct AppToneEditorSheet: View {
    let session: AppSession
    let application: ApplicationDescriptor?
    let profile: AppToneProfile?
    let save: (AppToneProfile) -> Void
    let cancel: () -> Void
    @State private var instruction: String
    @State private var preview = ""
    @State private var isPreviewing = false
    @State private var enabled: Bool

    init(
        session: AppSession,
        application: ApplicationDescriptor?,
        profile: AppToneProfile?,
        save: @escaping (AppToneProfile) -> Void,
        cancel: @escaping () -> Void
    ) {
        self.session = session
        self.application = application
        self.profile = profile
        self.save = save
        self.cancel = cancel
        _instruction = State(initialValue: profile?.instruction ?? "")
        _enabled = State(initialValue: profile?.enabled ?? true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ApplicationIcon(data: application?.iconData, name: applicationName)
                Text(verbatim: applicationName)
                    .lerroTypography(.title)
                Spacer()
                Toggle("启用", isOn: $enabled)
                    .toggleStyle(.switch)
            }

            TextEditor(text: $instruction)
                .font(LerroTheme.font(14))
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: 100)
                .background(LerroTheme.main)
                .clipShape(RoundedRectangle(cornerRadius: LerroTheme.controlRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: LerroTheme.controlRadius, style: .continuous)
                        .stroke(LerroTheme.thinBorder)
                }
                .onChange(of: instruction) { _, _ in preview = "" }

            HStack {
                Button {
                    runPreview()
                } label: {
                    Text(LocalizedStringKey(
                        isPreviewing ? "正在运行 AI 预览" : "运行 AI 预览"
                    ))
                }
                .buttonStyle(LerroPillButtonStyle(prominent: preview.isEmpty))
                .disabled(trimmedInstruction.isEmpty || isPreviewing || application == nil)
                Spacer()
            }

            if !preview.isEmpty {
                Text(verbatim: preview)
                    .font(LerroTheme.font(13))
                    .padding(14)
                    .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
                    .background(LerroTheme.fillContainerThin)
                    .clipShape(RoundedRectangle(cornerRadius: LerroTheme.controlRadius, style: .continuous))
            }

            HStack {
                Spacer()
                Button("取消", action: cancel)
                    .buttonStyle(LerroPillButtonStyle())
                Button("保存") { saveProfile() }
                    .buttonStyle(LerroPillButtonStyle(prominent: true))
                    .disabled(trimmedInstruction.isEmpty || preview.isEmpty || application == nil)
            }
        }
        .padding(24)
        .frame(width: 520, height: 430)
        .background(LerroTheme.main)
    }

    private func runPreview() {
        guard let application else { return }
        isPreviewing = true
        Task { @MainActor in
            preview = await session.previewAppTone(
                application: application,
                instruction: trimmedInstruction
            ) ?? ""
            isPreviewing = false
        }
    }

    private func saveProfile() {
        guard let application else { return }
        save(AppToneProfile(
            bundleIdentifier: application.bundleIdentifier,
            applicationName: application.name,
            instruction: trimmedInstruction,
            enabled: enabled
        ))
    }

    private var applicationName: String {
        application?.name ?? profile?.applicationName ?? "应用"
    }

    private var trimmedInstruction: String {
        instruction.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct ApplicationIcon: View {
    let data: Data?
    let name: String

    var body: some View {
        Group {
            if let data, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "app.fill")
                    .resizable()
                    .scaledToFit()
                    .padding(7)
                    .foregroundStyle(LerroTheme.secondaryText)
            }
        }
        .frame(width: 34, height: 34)
        .accessibilityLabel(Text(verbatim: name))
    }
}

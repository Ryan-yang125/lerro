import SwiftUI
import LerroCore

private enum ToneSelection: Hashable {
    case defaultTone
    case app(String)
    case pending
}

private struct ToneTarget: Equatable {
    enum Kind { case defaultTone, app, pending }

    var kind: Kind
    var bundleIdentifier: String
    var name: String
    var instruction: String

    var id: String { "\(kind)-\(bundleIdentifier)" }
}

struct AppTonesView: View {
    @Bindable var session: AppSession
    @State private var selection: ToneSelection = .defaultTone
    @State private var pendingApplication: ApplicationDescriptor?
    @State private var isPickerPresented = false
    @Environment(\.locale) private var locale

    private let columns = [GridItem(.adaptive(minimum: 220), spacing: 12, alignment: .top)]

    var body: some View {
        let target = currentTarget
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    AppToneCard(
                        name: localized("其他所有应用"),
                        bundleIdentifier: nil,
                        instruction: session.preferences.defaultToneInstruction,
                        footer: "默认",
                        isSelected: target.kind == .defaultTone,
                        isEnabled: nil,
                        select: { selection = .defaultTone }
                    )

                    ForEach(session.preferences.appToneProfiles) { profile in
                        AppToneCard(
                            name: profile.applicationName,
                            bundleIdentifier: profile.bundleIdentifier,
                            instruction: profile.instruction,
                            footer: profile.enabled ? "已启用" : "已停用",
                            isSelected: target.kind == .app && target.bundleIdentifier == profile.bundleIdentifier,
                            isEnabled: enabledBinding(for: profile.bundleIdentifier),
                            select: { selection = .app(profile.bundleIdentifier) }
                        )
                    }

                    if let pendingApplication {
                        AppToneCard(
                            name: pendingApplication.name,
                            bundleIdentifier: pendingApplication.bundleIdentifier,
                            instruction: "",
                            footer: "未保存",
                            isSelected: target.kind == .pending,
                            isEnabled: nil,
                            select: { selection = .pending }
                        )
                    }

                    addTile
                }

                AppToneEditor(
                    session: session,
                    target: target,
                    save: { save($0, for: target) },
                    remove: { remove(target) }
                )
                .id(target.id)
            }
            .padding(.horizontal, LerroTheme.contentHorizontalPadding)
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
        .background(LerroTheme.main)
        .navigationTitle(Text("应用语气"))
        .toolbar {
            ToolbarItem {
                Button {
                    isPickerPresented = true
                } label: {
                    Label("添加应用", systemImage: "plus")
                }
                .buttonStyle(LerroButtonStyle(.primary))
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .task {
            session.refreshAvailableApplications()
            if session.visualFixturePresentation == "app-tone-picker" {
                isPickerPresented = true
            }
        }
        .sheet(isPresented: $isPickerPresented) {
            AppTonePickerSheet(
                applications: session.availableApplications,
                dictationCounts: session.applicationDictationCounts,
                excludedBundleIdentifiers: Set(session.preferences.appToneProfiles.map(\.bundleIdentifier)),
                select: { application in
                    pendingApplication = application
                    selection = .pending
                    isPickerPresented = false
                },
                cancel: { isPickerPresented = false }
            )
        }
    }

    private var addTile: some View {
        Button {
            isPickerPresented = true
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .regular))
                Text("添加应用")
                    .font(LerroFont.caption)
            }
            .foregroundStyle(LerroTheme.secondaryText)
            .frame(maxWidth: .infinity, minHeight: AppToneCard.minimumHeight)
            .overlay {
                RoundedRectangle(cornerRadius: LerroTheme.cardRadius, style: .continuous)
                    .strokeBorder(
                        LerroTheme.border,
                        style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: LerroTheme.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Selection

    private var currentTarget: ToneTarget {
        switch selection {
        case .app(let bundleIdentifier):
            if let profile = session.preferences.appToneProfiles.first(where: {
                $0.bundleIdentifier == bundleIdentifier
            }) {
                return ToneTarget(
                    kind: .app,
                    bundleIdentifier: profile.bundleIdentifier,
                    name: profile.applicationName,
                    instruction: profile.instruction
                )
            }
        case .pending:
            if let pendingApplication {
                return ToneTarget(
                    kind: .pending,
                    bundleIdentifier: pendingApplication.bundleIdentifier,
                    name: pendingApplication.name,
                    instruction: ""
                )
            }
        case .defaultTone:
            break
        }
        return ToneTarget(
            kind: .defaultTone,
            bundleIdentifier: "",
            name: localized("其他所有应用"),
            instruction: session.preferences.defaultToneInstruction
        )
    }

    private func enabledBinding(for bundleIdentifier: String) -> Binding<Bool> {
        Binding(
            get: {
                session.preferences.appToneProfiles.first { $0.bundleIdentifier == bundleIdentifier }?.enabled ?? false
            },
            set: { enabled in
                guard var profile = session.preferences.appToneProfiles.first(where: {
                    $0.bundleIdentifier == bundleIdentifier
                }) else { return }
                profile.enabled = enabled
                session.saveAppToneProfile(profile)
            }
        )
    }

    private func save(_ instruction: String, for target: ToneTarget) {
        switch target.kind {
        case .defaultTone:
            session.preferences.defaultToneInstruction = instruction
            session.savePreferences()
        case .app:
            guard var profile = session.preferences.appToneProfiles.first(where: {
                $0.bundleIdentifier == target.bundleIdentifier
            }) else { return }
            profile.instruction = instruction
            session.saveAppToneProfile(profile)
        case .pending:
            session.saveAppToneProfile(AppToneProfile(
                bundleIdentifier: target.bundleIdentifier,
                applicationName: target.name,
                instruction: instruction,
                enabled: true
            ))
            pendingApplication = nil
            selection = .app(target.bundleIdentifier)
        }
    }

    private func remove(_ target: ToneTarget) {
        switch target.kind {
        case .defaultTone:
            break
        case .app:
            if let profile = session.preferences.appToneProfiles.first(where: {
                $0.bundleIdentifier == target.bundleIdentifier
            }) {
                session.deleteAppToneProfile(profile)
            }
        case .pending:
            pendingApplication = nil
        }
        selection = .defaultTone
    }

    private func localized(_ key: String) -> String {
        LerroInterfaceLocalization.string(key, locale: locale)
    }
}

// MARK: - Card

private struct AppToneCard: View {
    static let minimumHeight: CGFloat = 116

    let name: String
    let bundleIdentifier: String?
    let instruction: String
    let footer: String
    let isSelected: Bool
    let isEnabled: Binding<Bool>?
    let select: () -> Void
    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isDimmed: Bool { isEnabled?.wrappedValue == false }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    if bundleIdentifier == nil {
                        DefaultToneIcon(size: 32)
                    } else {
                        LerroAppIcon(bundleIdentifier: bundleIdentifier, name: name, size: 32)
                    }
                    Text(verbatim: name)
                        .font(LerroFont.bodyEmphasis)
                        .foregroundStyle(LerroTheme.text)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                Text(verbatim: instruction)
                    .font(LerroFont.body)
                    .foregroundStyle(LerroTheme.secondaryText)
                    .lineLimit(2, reservesSpace: true)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .opacity(isDimmed ? 0.55 : 1)

            HStack {
                Text(LocalizedStringKey(footer))
                    .font(LerroFont.caption)
                    .foregroundStyle(LerroTheme.metadataText)
                Spacer()
                if let isEnabled {
                    Toggle("启用", isOn: isEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .accessibilityLabel(Text(verbatim: name))
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: Self.minimumHeight, alignment: .topLeading)
        .background(
            isSelected ? LerroTheme.accentSoft : LerroTheme.topLayer,
            in: RoundedRectangle(cornerRadius: LerroTheme.cardRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: LerroTheme.cardRadius, style: .continuous)
                .strokeBorder(
                    isSelected ? LerroTheme.accent : (isHovering ? LerroTheme.borderHover : LerroTheme.thinBorder),
                    lineWidth: isSelected ? 1.5 : 1
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: LerroTheme.cardRadius, style: .continuous))
        .onTapGesture(perform: select)
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeOut(duration: LerroTheme.hoverDuration)) {
                isHovering = hovering
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: name))
        .accessibilityValue(Text(verbatim: instruction))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(.default, select)
    }
}

private struct DefaultToneIcon: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .fill(LinearGradient(
                    colors: [LerroTheme.accent, LerroTheme.accent.opacity(0.55)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            Image(systemName: "square.grid.2x2")
                .font(.system(size: size * 0.45, weight: .medium))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Editor

private struct AppToneEditor: View {
    let session: AppSession
    let target: ToneTarget
    let save: (String) -> Void
    let remove: () -> Void
    @State private var draft: String
    @State private var sample = "嗯那个晚上一起吃饭吗我大概八点到你们先点吧"
    @State private var previewedSample = ""
    @State private var previewResult: String?
    @State private var previewFailed = false
    @State private var isPreviewing = false
    @State private var previewTask: Task<Void, Never>?
    @State private var isDeleteConfirmationPresented = false
    @Environment(\.openSettings) private var openSettings

    init(session: AppSession, target: ToneTarget, save: @escaping (String) -> Void, remove: @escaping () -> Void) {
        self.session = session
        self.target = target
        self.save = save
        self.remove = remove
        _draft = State(initialValue: target.instruction)
    }

    private var trimmedDraft: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedSample: String { sample.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canSave: Bool {
        guard trimmedDraft != target.instruction else { return false }
        return target.kind == .defaultTone || !trimmedDraft.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(alignment: .top, spacing: 20) {
                instructionColumn
                Divider()
                previewColumn
            }
            .padding(16)
        }
        .background(
            LerroTheme.topLayer,
            in: RoundedRectangle(cornerRadius: LerroTheme.cardRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: LerroTheme.cardRadius, style: .continuous)
                .strokeBorder(LerroTheme.thinBorder, lineWidth: 1)
        }
        .onDisappear { previewTask?.cancel() }
        .onChange(of: draft) { _, _ in
            previewResult = nil
            previewFailed = false
        }
        .confirmationDialog(
            Text("删除这个应用语气？"),
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive, action: remove)
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后无法恢复。")
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            if target.kind == .defaultTone {
                DefaultToneIcon(size: 24)
            } else {
                LerroAppIcon(bundleIdentifier: target.bundleIdentifier, name: target.name, size: 24)
            }
            Text(verbatim: target.name)
                .font(LerroFont.bodyEmphasis)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            switch target.kind {
            case .defaultTone:
                EmptyView()
            case .app:
                Button("删除") { isDeleteConfirmationPresented = true }
                    .buttonStyle(LerroButtonStyle(.secondary))
            case .pending:
                Button("取消", action: remove)
                    .buttonStyle(LerroButtonStyle(.secondary))
            }
            Button("保存") { save(trimmedDraft) }
                .buttonStyle(LerroButtonStyle(.primary))
                .disabled(!canSave)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var instructionColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("语气要求")
                .font(LerroFont.sectionLabel)
                .foregroundStyle(LerroTheme.secondaryText)
            TextEditor(text: $draft)
                .font(LerroFont.body)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 150, maxHeight: .infinity)
                .background(
                    LerroTheme.fillContainerThin,
                    in: RoundedRectangle(cornerRadius: LerroTheme.controlRadius, style: .continuous)
                )
                .accessibilityLabel(Text("语气要求"))
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var previewColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("试一句")
                .font(LerroFont.sectionLabel)
                .foregroundStyle(LerroTheme.secondaryText)

            if session.selectedAIIsReady {
                TextField("示例句子", text: $sample, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...3)

                previewResultBox

                Button {
                    runPreview()
                } label: {
                    Label(
                        LocalizedStringKey(previewResult == nil ? "用 AI 试一下" : "用 AI 再试一次"),
                        systemImage: "arrow.clockwise"
                    )
                }
                .buttonStyle(LerroButtonStyle(.secondary))
                .disabled(isPreviewing || trimmedDraft.isEmpty || trimmedSample.isEmpty)
            } else {
                HStack(spacing: 10) {
                    Text("需要先开启 AI")
                        .font(LerroFont.body)
                        .foregroundStyle(LerroTheme.secondaryText)
                    Button("启用 AI") {
                        session.settingsTab = .intelligence
                        openSettings()
                    }
                    .buttonStyle(LerroButtonStyle(.secondary))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var previewResultBox: some View {
        if isPreviewing {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("正在生成")
                    .font(LerroFont.body)
                    .foregroundStyle(LerroTheme.secondaryText)
            }
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .padding(.horizontal, 12)
            .background(previewBoxBackground)
        } else if let previewResult {
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: "“\(previewedSample)”")
                    .font(LerroFont.caption)
                    .foregroundStyle(LerroTheme.secondaryText)
                Text(verbatim: previewResult)
                    .font(LerroFont.body)
                    .foregroundStyle(LerroTheme.text)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(previewBoxBackground)
            .accessibilityElement(children: .combine)
        } else if previewFailed {
            Text("AI 没有返回结果")
                .font(LerroFont.body)
                .foregroundStyle(LerroTheme.secondaryText)
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                .padding(.horizontal, 12)
                .background(previewBoxBackground)
        }
    }

    private var previewBoxBackground: some View {
        RoundedRectangle(cornerRadius: LerroTheme.controlRadius, style: .continuous)
            .fill(LerroTheme.fillContainerThin)
    }

    private func runPreview() {
        let instruction = trimmedDraft
        let text = trimmedSample
        guard !instruction.isEmpty, !text.isEmpty else { return }
        previewTask?.cancel()
        isPreviewing = true
        previewFailed = false
        previewResult = nil
        previewedSample = text
        let application = ApplicationDescriptor(
            bundleIdentifier: target.bundleIdentifier,
            name: target.name
        )
        previewTask = Task { @MainActor in
            let output = await session.previewAppTone(
                application: application,
                instruction: instruction,
                sample: text
            )
            guard !Task.isCancelled else { return }
            previewResult = output
            previewFailed = output == nil
            isPreviewing = false
        }
    }
}

import AppKit
import SwiftUI
import LerroCore

/// Three steps to get a DeepSeek API key, a key field that connects as soon as
/// a complete key is pasted, and one status line for the connection result.
struct DeepSeekKeyGuide: View {
    @Bindable var session: AppSession
    let showsCostHint: Bool
    let onConnected: () -> Void

    @Environment(\.locale) private var locale

    @State private var keyText = ""
    @State private var state: GuideState
    @State private var lastAttemptedKey: String?
    @State private var isConnecting = false
    @State private var connectTask: Task<Void, Never>?

    private enum GuideState: Equatable {
        case idle
        case checking
        case connected
        case noBalance
        case invalidKey
        case failed(String)
    }

    init(session: AppSession, showsCostHint: Bool = true, onConnected: @escaping () -> Void = {}) {
        self.session = session
        self.showsCostHint = showsCostHint
        self.onConnected = onConnected
        let initialState: GuideState = switch session.aiStatus {
        case .ready: .connected
        case .outOfBalance: .noBalance
        case .off: .idle
        }
        _state = State(initialValue: initialState)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            stepRow(
                number: 1,
                title: "登录 DeepSeek 开放平台",
                detail: "手机号就能注册",
                action: "打开网站",
                url: DeepSeekLinks.platform
            )
            Divider()
            stepRow(
                number: 2,
                title: "充值 10 元",
                detail: "每天说一百多次，一个月 2 块钱左右",
                action: "去充值",
                url: DeepSeekLinks.topUp
            )
            Divider()
            stepRow(
                number: 3,
                title: "创建 API Key，复制后粘贴到下面",
                detail: "Key 只在创建时显示一次",
                action: "去创建",
                url: DeepSeekLinks.apiKeys,
                done: state == .connected
            )
            keyRow
            if state != .idle {
                statusLine
            }
        }
        .padding(.bottom, 14)
        .background(LerroTheme.topLayer, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(LerroTheme.thinBorder, lineWidth: 0.5)
        }
        .onChange(of: keyText) { _, updated in
            let key = updated.trimmingCharacters(in: .whitespacesAndNewlines)
            guard state != .connected, !isConnecting else { return }
            if Self.isCompleteKey(key) {
                if key != lastAttemptedKey { connect(key) }
            } else if state != .idle {
                state = .idle
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            retryAfterReturningToApp()
        }
        .onDisappear {
            connectTask?.cancel()
            connectTask = nil
        }
    }

    // MARK: Header and rows

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("三步拿到 DeepSeek Key")
                .font(LerroFont.bodyEmphasis)
                .foregroundStyle(LerroTheme.text)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if showsCostHint {
                Text("约 2 元/月")
                    .font(LerroFont.caption)
                    .foregroundStyle(LerroTheme.metadataText)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 13)
        .padding(.bottom, 4)
    }

    private func stepRow(
        number: Int,
        title: String,
        detail: String,
        action: String,
        url: URL,
        done: Bool = false
    ) -> some View {
        HStack(spacing: 10) {
            numberBadge(number, done: done)
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(title))
                    .font(LerroFont.bodyEmphasis)
                    .foregroundStyle(LerroTheme.text)
                Text(LocalizedStringKey(detail))
                    .font(LerroFont.caption)
                    .foregroundStyle(LerroTheme.metadataText)
            }
            Spacer(minLength: 12)
            Button {
                session.openURL(url)
            } label: {
                HStack(spacing: 4) {
                    Text(LocalizedStringKey(action))
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .semibold))
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(LerroButtonStyle(.secondary, compact: true))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    private func numberBadge(_ number: Int, done: Bool) -> some View {
        ZStack {
            Circle().fill(done ? LerroTheme.success : LerroTheme.fillContainerTough)
            if done {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.white)
            } else {
                Text(verbatim: "\(number)")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(LerroTheme.secondaryText)
            }
        }
        .frame(width: 22, height: 22)
        .accessibilityHidden(true)
    }

    // MARK: Key field

    private var keyRow: some View {
        HStack(spacing: 8) {
            SecureField("sk- 开头的一串字符", text: $keyText)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .privacySensitive()
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(LerroTheme.main, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(LerroTheme.thinBorder, lineWidth: 0.5)
                }
                .accessibilityLabel(Text(verbatim: "DeepSeek API Key"))
                .onSubmit {
                    let key = keyText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if Self.isCompleteKey(key), state != .connected, !isConnecting { connect(key) }
                }
            PasteButton(payloadType: String.self) { strings in
                guard let pasted = strings.first else { return }
                keyText = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .labelStyle(.titleOnly)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
        }
        .padding(.leading, 48)
        .padding(.trailing, 16)
        .padding(.top, 4)
        .padding(.bottom, state == .idle ? 0 : 12)
    }

    // MARK: Status

    @ViewBuilder
    private var statusLine: some View {
        switch state {
        case .idle:
            EmptyView()
        case .checking:
            statusRow(color: LerroTheme.secondaryText, background: LerroTheme.fillContainerThin) {
                ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 14, height: 14)
                Text("正在连接 DeepSeek…")
            }
        case .connected:
            statusRow(color: LerroTheme.success, background: LerroTheme.success.opacity(0.12)) {
                Image(systemName: "checkmark.circle")
                Text("已连接，AI 整理已开启")
            }
        case .noBalance:
            statusRow(color: LerroTheme.warning, background: LerroTheme.warning.opacity(0.14)) {
                Image(systemName: "exclamationmark.circle")
                Text("Key 没问题，账户里还没有余额")
                Spacer()
                Button("去充值") { session.openURL(DeepSeekLinks.topUp) }
                    .buttonStyle(.plain)
                    .foregroundStyle(LerroTheme.accentText)
            }
        case .invalidKey:
            statusRow(color: LerroTheme.danger, background: LerroTheme.danger.opacity(0.10)) {
                Image(systemName: "exclamationmark.circle")
                Text("这个 Key 用不了，检查一下是不是复制完整了")
            }
        case .failed(let message):
            statusRow(color: LerroTheme.danger, background: LerroTheme.danger.opacity(0.10)) {
                Image(systemName: "exclamationmark.circle")
                Text(verbatim: LerroInterfaceLocalization.string(message, locale: locale))
            }
        }
    }

    private func statusRow<Content: View>(
        color: Color,
        background: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 7) { content() }
            .font(.system(size: 12.5))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.leading, 48)
            .padding(.trailing, 16)
            .accessibilityElement(children: .combine)
    }

    // MARK: Connecting

    private static func isCompleteKey(_ key: String) -> Bool {
        key.count >= 30 && key.hasPrefix("sk-")
    }

    private func connect(_ key: String, silently: Bool = false) {
        guard !isConnecting else { return }
        isConnecting = true
        lastAttemptedKey = key
        if !silently { state = .checking }
        connectTask?.cancel()
        connectTask = Task { @MainActor in
            let outcome = await session.connectDeepSeek(apiKey: key)
            isConnecting = false
            guard !Task.isCancelled else { return }
            switch outcome {
            case .connected:
                state = .connected
                onConnected()
            case .noBalance:
                state = .noBalance
            case .invalidKey:
                lastAttemptedKey = nil
                state = .invalidKey
            case .failed(let message):
                lastAttemptedKey = nil
                state = .failed(message)
            }
        }
    }

    /// After the user tops up on the DeepSeek site and comes back, check the
    /// same key once without showing the connecting state.
    private func retryAfterReturningToApp() {
        guard state == .noBalance, !isConnecting else { return }
        let key = lastAttemptedKey ?? keyText.trimmingCharacters(in: .whitespacesAndNewlines)
        if Self.isCompleteKey(key) {
            connect(key, silently: true)
            return
        }
        isConnecting = true
        connectTask = Task { @MainActor in
            await session.refreshDeepSeekBalance(force: true)
            isConnecting = false
            guard !Task.isCancelled, session.aiStatus == .ready else { return }
            state = .connected
            onConnected()
        }
    }
}

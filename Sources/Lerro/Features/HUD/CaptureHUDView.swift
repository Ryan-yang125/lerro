import AppKit
import SwiftUI
import LerroCore

private enum HUDContent: Hashable {
    case flat
    case preparingSpeech
    case listening
    case liveText
    case silence
    case polishing
    case deliveredRawFallback
    case error
    case recovery
    case dictionaryLearned
}

private struct HUDLayoutKey: Equatable {
    var content: HUDContent
    var showsTimer: Bool
    var showsHint: Bool
    var showsCancel: Bool
    var liveText: String
}

struct CaptureHUDView: View {
    let session: AppSession
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.colorSchemeContrast) private var systemContrast
    @Environment(\.locale) private var locale
    @State private var transcriptAnnouncementTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .bottom) {
            if visualState != .idleHidden {
                capsule
                    .transition(presenceTransition)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, LerroTheme.hudContentBottomInset)
        .animation(presenceAnimation, value: visualState == .idleHidden)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
        .accessibilityHidden(visualState == .idleHidden)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityActions {
            if canEnterHandsFree {
                Button("进入免按住模式") {
                    session.enterHandsFreeCapture(session.activeMode)
                }
            }
        }
        .onChange(of: visualState) { previous, current in
            announceTransition(from: previous, to: current)
        }
        .onChange(of: session.partialTranscript, initial: true) { _, transcript in
            scheduleTranscriptAnnouncement(transcript)
        }
        .onDisappear { transcriptAnnouncementTask?.cancel() }
    }

    private var capsule: some View {
        ZStack {
            contentView
                .id(content)
                .transition(.opacity)
        }
        .padding(.horizontal, LerroTheme.hudHorizontalPadding)
        .fixedSize(horizontal: true, vertical: false)
        .frame(height: LerroTheme.hudCapsuleHeight)
        .modifier(HUDSurface(
            reduceTransparency: reduceTransparency,
            increaseContrast: increaseContrast
        ))
        .animation(layoutAnimation, value: layoutKey)
        .onHover { isHovering in
            guard visualState == .dictionaryLearned else { return }
            session.setDictionaryLearningToastHoverPaused(isHovering)
        }
        .onTapGesture(count: 2) {
            guard canEnterHandsFree else { return }
            session.enterHandsFreeCapture(session.activeMode)
        }
    }

    @ViewBuilder
    private var contentView: some View {
        switch content {
        case .flat:
            HStack(spacing: LerroTheme.hudContentSpacing) {
                directionChip
                HUDCursor(blinks: false, reduceMotion: reduceMotion)
                HUDFlatWaveform(increaseContrast: increaseContrast)
            }
        case .preparingSpeech:
            HStack(spacing: LerroTheme.hudContentSpacing) {
                directionChip
                HUDCursor(blinks: false, reduceMotion: reduceMotion)
                HUDFlatWaveform(increaseContrast: increaseContrast)
                Text(verbatim: localized("正在准备语音资源"))
                    .font(LerroTheme.font(13))
                    .foregroundStyle(secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 260, alignment: .leading)
            }
        case .listening:
            HStack(spacing: LerroTheme.hudContentSpacing) {
                directionChip
                HUDCursor(blinks: true, reduceMotion: reduceMotion)
                HUDWaveform(
                    level: session.audioLevel,
                    reduceMotion: reduceMotion,
                    increaseContrast: increaseContrast
                )
                listeningAccessories
            }
        case .liveText:
            HStack(spacing: LerroTheme.hudContentSpacing) {
                HUDApplicationIconView(bundleIdentifier: session.activeCaptureBundleIdentifier)
                HUDLiveText(
                    text: liveTranscript,
                    isStable: session.partialTranscriptIsStable,
                    maximumWidth: liveTextMaximumWidth,
                    reduceMotion: reduceMotion
                )
                listeningAccessories
            }
        case .silence:
            HStack(spacing: LerroTheme.hudContentSpacing) {
                HUDCursor(blinks: false, reduceMotion: reduceMotion)
                HUDFlatWaveform(increaseContrast: increaseContrast)
                Text(verbatim: silenceText)
                    .font(LerroTheme.font(13))
                    .foregroundStyle(secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 260, alignment: .leading)
                listeningAccessories
            }
        case .polishing:
            HStack(spacing: LerroTheme.hudContentSpacing) {
                HUDApplicationIconView(bundleIdentifier: session.activeCaptureBundleIdentifier)
                HUDShimmerText(
                    text: localized(session.activeMode == .translation ? "翻译中…" : "AI 整理中…"),
                    reduceMotion: reduceMotion
                )
                if session.isCaptureCancellationAvailable {
                    HUDCircleButton(
                        systemName: "xmark",
                        label: localized("取消处理"),
                        increaseContrast: increaseContrast
                    ) { session.cancelCapture() }
                }
            }
        case .deliveredRawFallback:
            HStack(spacing: LerroTheme.hudContentSpacing) {
                HUDDot(color: LerroTheme.hudWarning)
                Text(session.hudFallbackMessage ?? localized("已写入原文 · AI 未响应"))
                    .font(LerroTheme.font(13))
                    .foregroundStyle(secondaryText)
                    .lineLimit(1)
            }
        case .error:
            HStack(spacing: LerroTheme.hudContentSpacing) {
                HUDDot(color: LerroTheme.hudError)
                Text(verbatim: localized(session.captureError ?? "没有听到声音"))
                    .font(LerroTheme.font(14))
                    .foregroundStyle(LerroTheme.hudPaper)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 260, alignment: .leading)
                HUDPillButton(title: localized("重试"), increaseContrast: increaseContrast) {
                    session.toggleCapture(session.activeMode)
                }
            }
        case .recovery:
            recoveryContent
        case .dictionaryLearned:
            dictionaryLearnedContent
        }
    }

    @ViewBuilder
    private var directionChip: some View {
        if let label = session.activeTranslationDirectionLabel {
            Text(verbatim: label)
                .font(LerroTheme.font(11, weight: .medium))
                .foregroundStyle(LerroTheme.hudPaper.opacity(0.8))
                .padding(.horizontal, 7)
                .frame(height: 20)
                .background(LerroTheme.hudPaper.opacity(increaseContrast ? 0.24 : 0.14), in: Capsule())
        }
    }

    @ViewBuilder
    private var listeningAccessories: some View {
        if let timer {
            Text(verbatim: timer.text)
                .font(LerroTheme.font(13))
                .monospacedDigit()
                .foregroundStyle(timer.isWarning ? LerroTheme.hudWarning : secondaryText)
                .transition(.opacity)
        }
        if showsHandsFreeHint, let label = session.handsFreeStopKeyLabel {
            Text(verbatim: label)
                .font(LerroTheme.font(11))
                .foregroundStyle(LerroTheme.hudPaper.opacity(0.7))
                .frame(minWidth: 18, minHeight: 18)
                .padding(.horizontal, 3)
                .overlay {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(LerroTheme.hudPaper.opacity(0.3), lineWidth: 1)
                }
                .accessibilityHidden(true)
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private var recoveryContent: some View {
        if let recovery = session.recoveryPresentation {
            HStack(spacing: LerroTheme.hudContentSpacing) {
                HUDDot(color: LerroTheme.hudWarning)
                Text(verbatim: LerroInterfaceLocalization.format(
                    "未能写入 %@，已复制",
                    locale: locale,
                    arguments: recovery.applicationName
                ))
                .font(LerroTheme.font(14))
                .foregroundStyle(LerroTheme.hudPaper)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 280, alignment: .leading)
                HUDPillButton(title: localized("再次复制"), increaseContrast: increaseContrast) {
                    session.recopyRecoveryText()
                }
                HUDCircleButton(
                    systemName: "xmark",
                    label: localized("关闭恢复提示"),
                    increaseContrast: increaseContrast
                ) { session.dismissRecovery() }
            }
        }
    }

    @ViewBuilder
    private var dictionaryLearnedContent: some View {
        if let toast = session.dictionaryLearningToast {
            HStack(spacing: LerroTheme.hudContentSpacing) {
                Text(verbatim: "+")
                    .font(LerroTheme.font(16, weight: .bold))
                    .foregroundStyle(LerroTheme.hudCursor)
                    .accessibilityHidden(true)
                if toast.count > 1 {
                    Text(verbatim: LerroInterfaceLocalization.format(
                        "已学会 %d 项修正",
                        locale: locale,
                        arguments: Int32(toast.count)
                    ))
                    .font(LerroTheme.font(14))
                    .foregroundStyle(LerroTheme.hudPaper)
                    .lineLimit(1)
                } else {
                    HStack(spacing: 0) {
                        Text(verbatim: "\(toast.phrase) → ")
                            .font(LerroTheme.font(14))
                            .foregroundStyle(LerroTheme.hudPaper.opacity(0.7))
                        Text(verbatim: toast.replacement)
                            .font(LerroTheme.font(14, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 300, alignment: .leading)
                }
                HUDPillButton(title: localized("撤销"), increaseContrast: increaseContrast) {
                    session.undoDictionaryLearning()
                }
            }
        }
    }

    private var visualState: CaptureHUDVisualState {
        session.currentHUDVisualState
    }

    private var content: HUDContent {
        switch visualState {
        case .idleHidden:
            .flat
        case .arming:
            session.isWaitingForSpeechResources ? .preparingSpeech : .flat
        case .listening:
            if session.isSilenceWarningVisible { .silence }
            else if hasLiveText { .liveText }
            else { .listening }
        case .processing:
            session.activeCaptureUsesAI ? .polishing : .flat
        case .deliveredRawFallback: .deliveredRawFallback
        case .error: .error
        case .recovery: .recovery
        case .dictionaryLearned: .dictionaryLearned
        }
    }

    private var layoutKey: HUDLayoutKey {
        HUDLayoutKey(
            content: content,
            showsTimer: timer != nil,
            showsHint: showsHandsFreeHint,
            showsCancel: content == .polishing && session.isCaptureCancellationAvailable,
            liveText: content == .liveText ? liveTranscript : ""
        )
    }

    private var liveTranscript: String {
        session.partialTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasLiveText: Bool {
        !liveTranscript.isEmpty
    }

    private var showsHandsFreeHint: Bool {
        visualState == .listening
            && session.showsHandsFreeStopHint
            && session.handsFreeStopKeyLabel != nil
    }

    private var liveTextMaximumWidth: CGFloat {
        var width = LerroTheme.hudLiveTextMaximumWidth
        if timer != nil { width -= 48 }
        if showsHandsFreeHint { width -= 32 }
        return width
    }

    private var timer: (text: String, isWarning: Bool)? {
        guard visualState == .listening, session.captureElapsed >= 5 else { return nil }
        let elapsed = Int(session.captureElapsed)
        if elapsed >= 8 * 60 {
            let remaining = max(0, 9 * 60 - elapsed)
            return (String(format: "%d:%02d", remaining / 60, remaining % 60), true)
        }
        return (String(format: "%d:%02d", elapsed / 60, elapsed % 60), false)
    }

    private var silenceText: String {
        guard let device = session.silenceWarningDeviceName else {
            return localized("没有听到声音")
        }
        return LerroInterfaceLocalization.format(
            "%@ · 没有听到声音",
            locale: locale,
            arguments: device
        )
    }

    private var canEnterHandsFree: Bool {
        visualState == .listening && !session.isHandsFreeCapture
    }

    private var secondaryText: Color {
        increaseContrast ? LerroTheme.hudPaper.opacity(0.85) : LerroTheme.hudSecondaryText
    }

    private var presenceTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .scale(scale: 0.92, anchor: .bottom).combined(with: .opacity),
            removal: .modifier(active: HUDHiddenEffect(isHidden: true), identity: HUDHiddenEffect(isHidden: false))
        )
    }

    private var presenceAnimation: Animation {
        if reduceMotion { return .easeInOut(duration: 0.15) }
        return .easeOut(duration: visualState == .idleHidden ? 0.2 : 0.18)
    }

    private var layoutAnimation: Animation {
        reduceMotion
            ? .easeInOut(duration: 0.15)
            : .spring(response: 0.35, dampingFraction: 0.8)
    }

    private var reduceMotion: Bool {
        systemReduceMotion || session.visualFixtureReduceMotion
    }

    private var reduceTransparency: Bool {
        systemReduceTransparency || session.visualFixtureReduceTransparency
    }

    private var increaseContrast: Bool {
        systemContrast == .increased || session.visualFixtureIncreaseContrast
    }

    private var accessibilityLabel: String {
        switch visualState {
        case .deliveredRawFallback:
            // hudFallbackMessage is already localized by AppSession.
            session.hudFallbackMessage ?? localized("AI 未响应，已写入原文")
        case .error:
            localized(session.captureError ?? "听写失败，请重试")
        default:
            localized(accessibilityLabelKey)
        }
    }

    private var accessibilityLabelKey: String {
        switch visualState {
        case .idleHidden: "Lerro 已就绪"
        case .arming:
            session.isWaitingForSpeechResources ? "正在准备语音资源" : "正在准备麦克风"
        case .listening:
            if session.isSilenceWarningVisible { "没有听到声音" }
            else if session.isHandsFreeCapture { handsFreeAccessibilityLabel }
            else if session.activeMode == .translation { "正在翻译" }
            else { "正在听写" }
        case .processing:
            switch session.activeMode {
            case .dictation: "正在处理听写"
            case .translation: "正在翻译"
            }
        case .deliveredRawFallback: "AI 未响应，已写入原文"
        case .error: "听写失败，请重试"
        case .recovery: "写入失败，已复制到剪贴板"
        case .dictionaryLearned: "已将修正加入词典"
        }
    }

    private var handsFreeAccessibilityLabel: String {
        switch session.activeMode {
        case .dictation: "免按住听写中"
        case .translation: "免按住翻译中"
        }
    }

    private func announceTransition(
        from previous: CaptureHUDVisualState,
        to current: CaptureHUDVisualState
    ) {
        guard let message = CaptureHUDAnnouncement.message(
            from: previous,
            to: current,
            mode: session.activeMode,
            phase: session.phase,
            errorMessage: session.captureError
        ) else { return }
        NSAccessibility.post(
            element: NSApplication.shared,
            notification: .announcementRequested,
            userInfo: [
                .announcement: localized(message),
                .priority: NSAccessibilityPriorityLevel.high.rawValue
            ]
        )
    }

    private func scheduleTranscriptAnnouncement(_ transcript: String) {
        transcriptAnnouncementTask?.cancel()
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, visualState == .listening else { return }
        transcriptAnnouncementTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled, visualState == .listening else { return }
            NSAccessibility.post(
                element: NSApplication.shared,
                notification: .announcementRequested,
                userInfo: [
                    .announcement: trimmed,
                    .priority: NSAccessibilityPriorityLevel.low.rawValue
                ]
            )
        }
    }

    private func localized(_ key: String) -> String {
        LerroInterfaceLocalization.string(key, locale: locale)
    }
}

private struct HUDHiddenEffect: ViewModifier {
    let isHidden: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHidden ? 0.92 : 1, anchor: .bottom)
            .opacity(isHidden ? 0 : 1)
            .offset(y: isHidden ? 6 : 0)
    }
}

private struct HUDSurface: ViewModifier {
    let reduceTransparency: Bool
    let increaseContrast: Bool

    func body(content: Content) -> some View {
        surface(content)
            .overlay {
                Capsule().strokeBorder(
                    increaseContrast
                        ? LerroTheme.hudPaper.opacity(0.3)
                        : Color.white.opacity(0.1),
                    lineWidth: increaseContrast ? 1 : 0.5
                )
            }
            .shadow(color: .black.opacity(0.25), radius: 15, y: 8)
    }

    @ViewBuilder
    private func surface(_ content: Content) -> some View {
        if reduceTransparency {
            content.background(LerroTheme.hudInk, in: Capsule())
        } else {
            content
                .glassEffect(.regular.tint(LerroTheme.hudInk), in: Capsule())
                .background(LerroTheme.hudInk.opacity(0.86), in: Capsule())
        }
    }
}

private struct HUDCursor: View {
    let blinks: Bool
    let reduceMotion: Bool
    var height: CGFloat = 18

    var body: some View {
        if blinks, !reduceMotion {
            TimelineView(.periodic(
                from: Date(timeIntervalSinceReferenceDate: 0),
                by: 0.525
            )) { context in
                let step = Int(context.date.timeIntervalSinceReferenceDate / 0.525)
                bar.opacity(step.isMultiple(of: 2) ? 1 : 0.12)
            }
        } else {
            bar
        }
    }

    private var bar: some View {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(LerroTheme.hudCursor)
            .frame(width: 3, height: height)
            .accessibilityHidden(true)
    }
}

private struct HUDDot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .accessibilityHidden(true)
    }
}

private struct HUDPillButton: View {
    let title: String
    let increaseContrast: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(LerroTheme.font(13, weight: .medium))
                .foregroundStyle(LerroTheme.hudPaper)
                .padding(.horizontal, 11)
                .frame(height: 26)
                .background(
                    LerroTheme.hudPaper.opacity(increaseContrast ? 0.26 : 0.16),
                    in: Capsule()
                )
                .contentShape(Capsule())
        }
        .buttonStyle(LerroPressButtonStyle())
    }
}

private struct HUDCircleButton: View {
    let systemName: String
    let label: String
    let increaseContrast: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(LerroTheme.hudPaper)
                .frame(width: 22, height: 22)
                .background(
                    LerroTheme.hudPaper.opacity(increaseContrast ? 0.26 : 0.14),
                    in: Circle()
                )
                .contentShape(Circle())
        }
        .buttonStyle(LerroPressButtonStyle())
        .accessibilityLabel(label)
    }
}

@MainActor
private enum HUDApplicationIconCache {
    private static var images: [String: NSImage] = [:]

    static func image(for bundleIdentifier: String?) -> NSImage? {
        guard let bundleIdentifier else { return nil }
        if let cached = images[bundleIdentifier] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleIdentifier
        ) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        images[bundleIdentifier] = image
        return image
    }
}

private struct HUDApplicationIconView: View {
    let bundleIdentifier: String?

    var body: some View {
        if let image = HUDApplicationIconCache.image(for: bundleIdentifier) {
            Image(nsImage: image)
                .resizable()
                .frame(width: 20, height: 20)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .accessibilityHidden(true)
        }
    }
}

private struct HUDLiveText: View {
    let text: String
    let isStable: Bool
    let maximumWidth: CGFloat
    let reduceMotion: Bool
    @Environment(\.locale) private var locale
    @State private var naturalWidth: CGFloat = 0

    var body: some View {
        HStack(spacing: 3) {
            Text(verbatim: text)
                .font(LerroTheme.font(14))
                .foregroundStyle(LerroTheme.hudPaper.opacity(isStable ? 1 : 0.85))
                .lineLimit(1)
                .fixedSize()
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: {
                    naturalWidth = $0
                }
            HUDCursor(blinks: true, reduceMotion: reduceMotion, height: 16)
        }
        .frame(maxWidth: maximumWidth, alignment: .trailing)
        .clipped()
        .mask(alignment: .leading) {
            HStack(spacing: 0) {
                LinearGradient(
                    colors: [.clear, .black],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: naturalWidth + 6 > maximumWidth ? 36 : 0)
                Rectangle()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(LerroInterfaceLocalization.string("实时转写", locale: locale))
        .accessibilityValue(Text(verbatim: text))
    }
}

private struct HUDShimmerText: View {
    let text: String
    let reduceMotion: Bool

    var body: some View {
        if reduceMotion {
            label.foregroundStyle(LerroTheme.hudPaper.opacity(0.7))
        } else {
            TimelineView(.animation) { context in
                let phase = context.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 1.6) / 1.6
                label
                    .foregroundStyle(LerroTheme.hudPaper.opacity(0.6))
                    .overlay {
                        label
                            .foregroundStyle(LerroTheme.hudPaper)
                            .mask {
                                GeometryReader { proxy in
                                    LinearGradient(
                                        colors: [.clear, .white, .clear],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                    .frame(width: proxy.size.width * 0.4)
                                    .offset(x: (phase * 1.4 - 0.4) * proxy.size.width)
                                }
                            }
                    }
            }
        }
    }

    private var label: some View {
        Text(text)
            .font(LerroTheme.font(14))
            .lineLimit(1)
    }
}

private struct HUDFlatWaveform: View {
    let increaseContrast: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<HUDWaveformResponse.barCount, id: \.self) { _ in
                Capsule()
                    .fill(LerroTheme.hudPaper.opacity(increaseContrast ? 0.6 : 0.35))
                    .frame(width: 3, height: 3)
            }
        }
        .frame(height: HUDWaveformResponse.maximumBarHeight)
        .accessibilityHidden(true)
    }
}

struct HUDWaveformResponse: Equatable {
    static let barCount = 9
    static let maximumBarHeight: CGFloat = 18
    static let minimumBarHeight: CGFloat = 4

    private static let reducedMotionFactors: [CGFloat] = [
        0.32, 0.62, 0.86, 0.5, 1, 0.72, 0.4, 0.9, 0.56
    ]

    private(set) var normalizedBars: [CGFloat]
    private(set) var noiseFloor: CGFloat
    private(set) var envelope: CGFloat
    private(set) var frame: UInt64
    private(set) var lastCenter: Int
    private let seed: UInt64

    init(seed: UInt64 = 0x4C_45_52_52_4F) {
        normalizedBars = Array(repeating: 0, count: Self.barCount)
        noiseFloor = 0.18
        envelope = 0
        frame = 0
        lastCenter = 4
        self.seed = seed
    }

    mutating func advance(level: Float, reduceMotion: Bool) {
        frame &+= 1
        let rawLevel = min(1, max(0, CGFloat(level)))

        if reduceMotion {
            applyReducedMotion(level: rawLevel)
            return
        }
        advanceListening(level: rawLevel)
    }

    func barHeight(at index: Int) -> CGFloat {
        guard normalizedBars.indices.contains(index) else {
            return Self.minimumBarHeight
        }
        return Self.minimumBarHeight
            + normalizedBars[index] * (Self.maximumBarHeight - Self.minimumBarHeight)
    }

    private mutating func advanceListening(level: CGFloat) {
        if level < noiseFloor {
            noiseFloor += (level - noiseFloor) * 0.18
        } else {
            noiseFloor += (level - noiseFloor) * 0.004
        }
        noiseFloor = min(0.26, max(0.12, noiseFloor))

        let threshold = max(0.22, noiseFloor + 0.03)
        let normalized = min(1, max(0, (level - threshold) / (0.7 - threshold)))
        let energy = pow(normalized, 0.72)
        let responsiveness: CGFloat = energy > envelope ? 0.78 : 0.48
        envelope += (energy - envelope) * responsiveness

        let previous = normalizedBars
        var next = Array(repeating: CGFloat.zero, count: Self.barCount)
        for index in next.indices {
            let left = index > 0 ? previous[index - 1] : 0
            let right = index + 1 < Self.barCount ? previous[index + 1] : 0
            let release = 0.54 + randomUnit(channel: UInt64(index) &+ 11) * 0.14
            let diffusion = 0.52 + randomUnit(channel: UInt64(index) &+ 37) * 0.12
            next[index] = min(
                1,
                max(previous[index] * release, max(left, right) * diffusion)
            )
        }

        if energy > 0.025 {
            if frame.isMultiple(of: 2) {
                var center = 2 + Int(
                    randomUnit(channel: 83) * CGFloat(Self.barCount - 4)
                )
                if center == lastCenter {
                    center = center == Self.barCount - 3 ? center - 1 : center + 1
                }
                lastCenter = center
            }

            let pulse = max(energy, envelope)
            next[lastCenter] = max(next[lastCenter], pulse)
            for distance in 1...3 {
                let falloff = pow(0.6, CGFloat(distance))
                let leftIndex = lastCenter - distance
                if leftIndex >= 0 {
                    let variation = 0.82 + randomUnit(
                        channel: UInt64(101 + distance * 7)
                    ) * 0.18
                    next[leftIndex] = max(next[leftIndex], pulse * falloff * variation)
                }
                let rightIndex = lastCenter + distance
                if rightIndex < Self.barCount {
                    let variation = 0.82 + randomUnit(
                        channel: UInt64(149 + distance * 11)
                    ) * 0.18
                    next[rightIndex] = max(next[rightIndex], pulse * falloff * variation)
                }
            }
        } else {
            for index in next.indices {
                let roomTone = 0.012 + randomUnit(channel: UInt64(index) &+ 211) * 0.04
                next[index] = max(next[index], roomTone)
            }
        }

        normalizedBars = next.map { min(1, max(0, $0)) }
    }

    private mutating func applyReducedMotion(level: CGFloat) {
        let strength: CGFloat = switch level {
        case 0.58...: 1
        case 0.32...: 0.68
        default: 0.05
        }
        envelope = strength
        normalizedBars = Self.reducedMotionFactors.map { $0 * strength }
    }

    private func randomUnit(channel: UInt64) -> CGFloat {
        var value = seed
            &+ frame &* 0x9E37_79B9_7F4A_7C15
            &+ channel &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        value ^= value >> 31
        return CGFloat(Double(value >> 11) / 9_007_199_254_740_992)
    }
}

private struct HUDWaveform: View {
    let level: Float
    let reduceMotion: Bool
    let increaseContrast: Bool

    @State private var sampledLevel: Float = 0
    @State private var response = HUDWaveformResponse(
        seed: UInt64.random(in: 1...UInt64.max)
    )

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<HUDWaveformResponse.barCount, id: \.self) { index in
                Capsule()
                    .fill(LerroTheme.hudPaper.opacity(increaseContrast ? 1 : 0.9))
                    .frame(width: 3, height: HUDWaveformResponse.maximumBarHeight)
                    .scaleEffect(
                        y: response.barHeight(at: index)
                            / HUDWaveformResponse.maximumBarHeight,
                        anchor: .center
                    )
            }
        }
        .frame(height: HUDWaveformResponse.maximumBarHeight)
        .animation(
            reduceMotion ? nil : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.09),
            value: response.normalizedBars
        )
        .onChange(of: level, initial: true) { _, newValue in
            sampledLevel = newValue
            if reduceMotion {
                response.advance(level: newValue, reduceMotion: true)
            }
        }
        .task(id: reduceMotion) {
            response.advance(level: sampledLevel, reduceMotion: reduceMotion)
            guard !reduceMotion else { return }

            let clock = ContinuousClock()
            while !Task.isCancelled {
                try? await clock.sleep(for: .milliseconds(50))
                guard !Task.isCancelled else { return }
                response.advance(level: sampledLevel, reduceMotion: false)
            }
        }
        .accessibilityHidden(true)
    }
}

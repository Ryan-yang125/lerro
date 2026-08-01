import AppKit
import SwiftUI
import LerroCore

enum CaptureHUDVisualState: Equatable {
    case idleHidden
    case hover
    case waiting
    case listening
    case handsFree
    case processing
    case error

    var size: CGSize {
        switch self {
        case .idleHidden: CGSize(width: 40, height: 6)
        case .hover, .waiting, .listening, .processing, .error:
            CGSize(width: 70, height: 34)
        case .handsFree:
            CGSize(width: 116, height: 34)
        }
    }

    func interactionSize(countdownVisible: Bool) -> CGSize {
        var result = size
        if countdownVisible, self == .listening || self == .handsFree {
            result.width += 40
        }
        result.width = max(result.width, LerroTheme.hudMinimumInteractionSize.width)
        result.height = max(result.height, LerroTheme.hudMinimumInteractionSize.height)
        return result
    }

    static func resolve(
        phase: CapturePhase,
        isStartingCapture: Bool,
        isHandsFreeCapture: Bool,
        isHUDHovered: Bool,
        isSuppressed: Bool = false
    ) -> Self {
        if isSuppressed { return .idleHidden }
        if isStartingCapture {
            return isHandsFreeCapture ? .handsFree : .waiting
        }

        switch phase {
        case .idle:
            return isHUDHovered ? .hover : .idleHidden
        case .listening:
            return isHandsFreeCapture ? .handsFree : .listening
        case .transcribing, .enhancing, .inserting:
            return .processing
        case .failed:
            return .error
        case .success, .cancelled:
            return .idleHidden
        }
    }
}

enum CaptureHUDAnnouncement {
    static func message(
        from previous: CaptureHUDVisualState,
        to current: CaptureHUDVisualState,
        phase: CapturePhase,
        mode: CaptureMode,
        isStartingCapture: Bool = false,
        errorMessage: String? = nil
    ) -> String? {
        switch current {
        case .waiting: "正在准备麦克风"
        case .listening: "正在听写"
        case .handsFree where isStartingCapture: "已锁定，正在准备麦克风"
        case .handsFree:
            switch mode {
            case .dictation: "已锁定，免按住听写进行中"
            case .translation: "已锁定，免按住翻译进行中"
            case .ask: "已锁定，免按住问答进行中"
            }
        case .processing:
            switch mode {
            case .dictation: "正在处理听写"
            case .translation: "正在处理翻译"
            case .ask: "正在处理问答"
            }
        case .error: errorMessage ?? "听写失败，可以重试"
        case .idleHidden where phase == .cancelled: "听写已取消"
        case .idleHidden where previous == .processing: "听写完成"
        case .idleHidden, .hover: nil
        }
    }
}

struct CaptureHUDView: View {
    let session: AppSession
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency
    @Environment(\.colorSchemeContrast) private var systemContrast

    var body: some View {
        hudControl
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, LerroTheme.hudContentBottomInset)
            .onTapGesture(count: 2) { session.enterHandsFreeCapture(session.activeMode) }
            .accessibilityElement(children: .contain)
            .accessibilityHidden(visualState == .idleHidden)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityActions {
                if session.phase == .listening, !session.isHandsFreeCapture {
                    Button("进入免按住模式") {
                        session.enterHandsFreeCapture(session.activeMode)
                    }
                }
            }
            .onChange(of: visualState) { previous, current in
                announceTransition(from: previous, to: current)
            }
            .onChange(of: session.isStartingCapture) { wasStarting, isStarting in
                guard wasStarting,
                      !isStarting,
                      visualState == .handsFree,
                      session.phase == .listening else { return }
                announceTransition(from: .handsFree, to: .handsFree)
            }
    }

    private var hudControl: some View {
        HStack(spacing: 4) {
            hudButtonSlot(
                "xmark",
                label: visualState == .processing ? "取消处理" : "取消当前听写",
                isVisible: showsCancelButton
            ) {
                session.cancelCapture()
            }

            ZStack {
                if visualState == .hover {
                    HStack(spacing: 4) {
                        Image(systemName: modeIcon)
                            .font(.system(size: 12, weight: .semibold))
                        Text(session.preferredActivation(for: session.activeMode) == .hold ? "按住" : "点按")
                            .font(LerroTheme.font(10, weight: .medium))
                    }
                    .transition(.opacity)
                }

                if let waveformMode {
                    HStack(spacing: 4) {
                        HUDWaveform(
                            level: waveformLevel,
                            mode: waveformMode,
                            reduceMotion: reduceMotion,
                            increaseContrast: increaseContrast
                        )
                        countdownLabel
                    }
                    .transition(.opacity)
                }

                if visualState == .processing {
                    HUDProcessingIndicator(
                        reduceMotion: reduceMotion,
                        increaseContrast: increaseContrast
                    )
                        .accessibilityHidden(true)
                        .transition(.opacity)
                }

                if visualState == .error {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color(nsColor: .systemRed))
                        Button("重试") { session.toggleCapture(session.activeMode) }
                            .buttonStyle(LerroPressButtonStyle())
                            .font(LerroTheme.font(10, weight: .medium))
                    }
                    .transition(.opacity)
                }
            }
            .animation(crossfadeAnimation, value: visualState)

            hudButtonSlot(
                "checkmark",
                label: "完成并处理听写",
                isVisible: visualState == .handsFree
            ) {
                session.toggleCapture(session.activeMode)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, visualState == .handsFree ? 4 : 6)
        .padding(.vertical, visualState == .idleHidden ? 0 : 4)
        .frame(width: targetSize.width, height: targetSize.height)
        .background(background)
        .clipShape(Capsule())
        .overlay {
            Capsule().stroke(
                Color.white.opacity(increaseContrast ? 0.68 : 0.32),
                lineWidth: increaseContrast ? 1.5 : 1
            )
            .opacity(visualState == .idleHidden ? 0 : 1)
        }
        .shadow(color: .black.opacity(0.24), radius: 12, y: 6)
        .opacity(visualState == .idleHidden ? 0 : 1)
        .animation(surfaceAnimation, value: visualState)
        .animation(surfaceAnimation, value: targetSize)
    }

    private var waveformMode: HUDWaveformMode? {
        switch visualState {
        case .waiting: .waiting
        case .handsFree where session.isStartingCapture: .arming
        case .listening, .handsFree: .listening
        case .idleHidden, .hover, .processing, .error: nil
        }
    }

    private var waveformLevel: Float {
        waveformMode == .listening ? session.audioLevel : 0
    }

    private var showsCancelButton: Bool {
        visualState == .handsFree
            || (visualState == .processing && session.isCaptureCancellationAvailable)
    }

    private var surfaceAnimation: Animation? {
        guard !reduceMotion else { return nil }
        return .interpolatingSpring(
            mass: 0.9,
            stiffness: 420,
            damping: 36,
            initialVelocity: 0
        )
    }

    private var crossfadeAnimation: Animation? {
        guard !reduceMotion else { return nil }
        if visualState == .processing {
            return .timingCurve(0.23, 1, 0.32, 1, duration: 0.08)
        }
        return .interpolatingSpring(
            mass: 0.8,
            stiffness: 260,
            damping: 34,
            initialVelocity: 0
        )
    }

    private var controlDisclosureAnimation: Animation? {
        reduceMotion ? nil : .timingCurve(0.05, 0.6, 0.4, 0.95, duration: 0.2)
    }

    private var controlOpacityAnimation: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.1)
    }

    private var background: Color {
        Color.black.opacity(reduceTransparency ? 1 : 0.94)
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

    private var visualState: CaptureHUDVisualState {
        CaptureHUDVisualState.resolve(
            phase: session.phase,
            isStartingCapture: session.isStartingCapture,
            isHandsFreeCapture: session.isHandsFreeCapture,
            isHUDHovered: session.isHUDHovered,
            isSuppressed: session.isHUDSuppressed
        )
    }

    private var targetSize: CGSize {
        var size = visualState.size
        if isCountdownVisible { size.width += 40 }
        return size
    }

    private var isCountdownVisible: Bool {
        session.phase == .listening && session.captureElapsed >= 8 * 60
    }

    @ViewBuilder
    private var countdownLabel: some View {
        if isCountdownVisible {
            Text(timeRemaining)
                .font(LerroTheme.font(9, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(increaseContrast ? 1 : 0.84))
        }
    }

    private var timeRemaining: String {
        let remaining = max(0, 9 * 60 - Int(session.captureElapsed))
        return String(format: "%d:%02d", remaining / 60, remaining % 60)
    }

    private var modeIcon: String {
        switch session.activeMode {
        case .dictation: "waveform"
        case .translation: "character.bubble"
        case .ask: "sparkles"
        }
    }

    private var accessibilityLabel: String {
        switch visualState {
        case .idleHidden: "Lerro 已就绪"
        case .hover:
            session.preferredActivation(for: session.activeMode) == .hold
                ? "Lerro 听写控制，按住快捷键开始，松开后完成"
                : "Lerro 听写控制，按一次快捷键开始，再按一次完成"
        case .waiting: "正在准备麦克风"
        case .listening: "正在听写"
        case .handsFree: session.isStartingCapture
            ? "已锁定，正在准备麦克风"
            : handsFreeAccessibilityLabel
        case .processing:
            switch session.activeMode {
            case .dictation: "正在处理听写"
            case .translation: "正在处理翻译"
            case .ask: "正在处理问答"
            }
        case .error: session.captureError ?? "听写失败，可以重试"
        }
    }

    private var handsFreeAccessibilityLabel: String {
        switch session.activeMode {
        case .dictation: "已锁定，免按住听写进行中"
        case .translation: "已锁定，免按住翻译进行中"
        case .ask: "已锁定，免按住问答进行中"
        }
    }

    private func hudButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .frame(width: 24, height: 24)
                .background(Color.white.opacity(increaseContrast ? 0.26 : 0.13))
                .clipShape(Circle())
        }
        .buttonStyle(LerroPressButtonStyle())
        .accessibilityLabel(label)
    }

    private func hudButtonSlot(
        _ icon: String,
        label: String,
        isVisible: Bool,
        action: @escaping () -> Void
    ) -> some View {
        hudButton(icon, label: label, action: action)
            .opacity(isVisible ? 1 : 0)
            .animation(controlOpacityAnimation, value: isVisible)
            .frame(width: isVisible ? 24 : 0, height: 24)
            .scaleEffect(isVisible ? 1 : 0.01)
            .clipped()
            .allowsHitTesting(isVisible)
            .accessibilityHidden(!isVisible)
            .animation(controlDisclosureAnimation, value: isVisible)
    }

    private func announceTransition(
        from previous: CaptureHUDVisualState,
        to current: CaptureHUDVisualState
    ) {
        guard let message = CaptureHUDAnnouncement.message(
            from: previous,
            to: current,
            phase: session.phase,
            mode: session.activeMode,
            isStartingCapture: session.isStartingCapture,
            errorMessage: session.captureError
        ) else { return }
        NSAccessibility.post(
            element: NSApplication.shared,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.high.rawValue
            ]
        )
    }
}

struct HUDProcessingPulse: Equatable {
    static let dotCount = 3
    static let cycleDuration: TimeInterval = 0.72

    let energies: [CGFloat]

    init(elapsed: TimeInterval, reduceMotion: Bool) {
        if reduceMotion {
            energies = [0.18, 1, 0.18]
            return
        }

        let cycle = elapsed.truncatingRemainder(dividingBy: Self.cycleDuration)
            / Self.cycleDuration
        energies = (0..<Self.dotCount).map { index in
            let peak = Double(index) / Double(Self.dotCount)
            let directDistance = abs(cycle - peak)
            let wrappedDistance = min(directDistance, 1 - directDistance)
            return CGFloat(max(0, 1 - wrappedDistance / 0.34))
        }
    }
}

enum HUDProcessingIndicatorStyle {
    static let usesSystemAccent = true
    static let dotColor = LerroTheme.accent
}

private struct HUDProcessingIndicator: View {
    let reduceMotion: Bool
    let increaseContrast: Bool

    var body: some View {
        TimelineView(.animation(
            minimumInterval: 1.0 / 30.0,
            paused: reduceMotion
        )) { context in
            let pulse = HUDProcessingPulse(
                elapsed: context.date.timeIntervalSinceReferenceDate,
                reduceMotion: reduceMotion
            )

            HStack(spacing: 3) {
                ForEach(pulse.energies.indices, id: \.self) { index in
                    let energy = pulse.energies[index]
                    Circle()
                        .fill(HUDProcessingIndicatorStyle.dotColor.opacity(
                            dotOpacity(for: energy)
                        ))
                        .frame(width: 4, height: 4)
                        .scaleEffect(0.78 + energy * 0.28)
                }
            }
        }
        .frame(width: 26, height: 22)
    }

    private func dotOpacity(for energy: CGFloat) -> Double {
        let minimumOpacity = increaseContrast ? 0.62 : 0.36
        return minimumOpacity + Double(energy) * (1 - minimumOpacity)
    }
}

enum HUDWaveformMode: Hashable {
    case arming
    case waiting
    case listening
}

struct HUDWaveformResponse: Equatable {
    static let barCount = 10
    static let maximumBarHeight: CGFloat = 21
    static let minimumBarHeight: CGFloat = 3

    private static let reducedMotionFactors: [CGFloat] = [
        0.32, 0.62, 0.86, 0.5, 1, 0.72, 0.4, 0.9, 0.56, 0.76
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

    mutating func advance(
        level: Float,
        mode: HUDWaveformMode,
        reduceMotion: Bool
    ) {
        frame &+= 1
        let rawLevel = min(1, max(0, CGFloat(level)))

        if reduceMotion {
            applyReducedMotion(level: rawLevel, mode: mode)
            return
        }

        switch mode {
        case .arming:
            envelope = 0
            normalizedBars = Array(repeating: 0, count: Self.barCount)
        case .waiting:
            envelope = 0
            applyRoomTone(maximum: 0.1)
        case .listening:
            advanceListening(level: rawLevel)
        }
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

    private mutating func applyRoomTone(maximum: CGFloat) {
        normalizedBars = normalizedBars.indices.map { index in
            let target = 0.018 + randomUnit(channel: UInt64(index) &+ 263) * maximum
            return min(maximum, normalizedBars[index] * 0.58 + target * 0.42)
        }
    }

    private mutating func applyReducedMotion(level: CGFloat, mode: HUDWaveformMode) {
        let strength: CGFloat
        switch mode {
        case .arming:
            strength = 0
        case .waiting:
            strength = 0.1
        case .listening where level >= 0.58:
            strength = 1
        case .listening where level >= 0.32:
            strength = 0.68
        case .listening:
            strength = 0.05
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

private struct HUDWaveformTaskID: Hashable {
    let mode: HUDWaveformMode
    let reduceMotion: Bool
}

private struct HUDWaveform: View {
    let level: Float
    let mode: HUDWaveformMode
    let reduceMotion: Bool
    let increaseContrast: Bool

    @State private var sampledLevel: Float = 0
    @State private var response = HUDWaveformResponse(
        seed: UInt64.random(in: 1...UInt64.max)
    )

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<HUDWaveformResponse.barCount, id: \.self) { index in
                Capsule()
                    .fill(Color.white.opacity(barOpacity))
                    .frame(width: 2, height: HUDWaveformResponse.maximumBarHeight)
                    .scaleEffect(
                        y: response.barHeight(at: index)
                            / HUDWaveformResponse.maximumBarHeight,
                        anchor: .center
                    )
            }
        }
        .frame(width: 38, height: 22)
        .animation(
            reduceMotion ? nil : .timingCurve(0.2, 0.8, 0.2, 1, duration: 0.09),
            value: response.normalizedBars
        )
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.12),
            value: mode
        )
        .onChange(of: level, initial: true) { _, newValue in
            sampledLevel = newValue
            if reduceMotion {
                response.advance(level: newValue, mode: mode, reduceMotion: true)
            }
        }
        .task(id: HUDWaveformTaskID(mode: mode, reduceMotion: reduceMotion)) {
            response.advance(level: sampledLevel, mode: mode, reduceMotion: reduceMotion)
            guard !reduceMotion, mode != .arming else { return }

            let clock = ContinuousClock()
            do {
                while !Task.isCancelled {
                    try await clock.sleep(for: .milliseconds(50))
                    guard !Task.isCancelled else { return }
                    response.advance(level: sampledLevel, mode: mode, reduceMotion: false)
                }
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
        .accessibilityHidden(true)
    }

    private var barOpacity: Double {
        if mode == .arming { return increaseContrast ? 0.78 : 0.5 }
        return increaseContrast ? 1 : 0.9
    }
}

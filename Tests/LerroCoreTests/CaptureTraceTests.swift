import Foundation
import Testing
@testable import LerroCore

@Suite("Capture trace")
struct CaptureTraceTests {
    private let origin = ContinuousClock.now

    private func at(_ milliseconds: Int) -> ContinuousClock.Instant {
        origin.advanced(by: .milliseconds(milliseconds))
    }

    private func makeTrace(id: UUID = UUID(), handledAtMilliseconds: Int = 10) -> CaptureTrace {
        CaptureTrace(
            id: id,
            mode: .dictation,
            intelligenceMode: .raw,
            pressedAt: origin,
            handledAt: at(handledAtMilliseconds)
        )
    }

    private func isClose(_ value: TimeInterval?, to expected: TimeInterval) -> Bool {
        guard let value else { return false }
        return abs(value - expected) < 1e-9
    }

    // MARK: CaptureTrace

    @Test("init records the key press at offset zero and the handled instant")
    func initMarks() {
        let trace = makeTrace()
        #expect(isClose(trace.offset(of: .hotkeyPressed), to: 0))
        #expect(isClose(trace.offset(of: .hotkeyHandled), to: 0.010))
        #expect(trace.offset(of: .listening) == nil)
        #expect(!trace.isFinished)
    }

    @Test("the first mark of a milestone wins")
    func firstMarkWins() {
        var trace = makeTrace()
        let result1 = trace.mark(.listening, at: at(400))
        #expect(result1)
        let result2 = !trace.mark(.listening, at: at(900))
        #expect(result2)
        #expect(trace.instants[.listening] == at(400))
    }

    @Test("finished cannot be marked, only finished")
    func finishedMilestoneRejected() {
        var trace = makeTrace()
        let result3 = !trace.mark(.finished, at: at(500))
        #expect(result3)
        #expect(trace.instants[.finished] == nil)
        #expect(!trace.isFinished)
    }

    @Test("a finished trace rejects marks and a second finish")
    func finishOnce() {
        var trace = makeTrace()
        let result4 = trace.mark(.listening, at: at(400))
        #expect(result4)
        let result5 = trace.finish(.completed, at: at(900))
        #expect(result5)
        #expect(trace.isFinished)
        #expect(trace.outcome == .completed)
        let result6 = !trace.mark(.stopRequested, at: at(1_000))
        #expect(result6)
        let result7 = !trace.finish(.failed, errorKind: "x", at: at(1_100))
        #expect(result7)
        #expect(trace.outcome == .completed)
        #expect(trace.errorKind == nil)
        #expect(trace.instants[.finished] == at(900))
    }

    @Test("offsets and segment durations")
    func offsetsAndDurations() {
        var trace = makeTrace()
        trace.mark(.speechStartRequested, at: at(120))
        trace.mark(.listening, at: at(412))
        trace.mark(.stopRequested, at: at(2_412))
        #expect(isClose(trace.offset(of: .listening), to: 0.412))
        #expect(isClose(trace.duration(of: .readyToSpeak), to: 0.412))
        #expect(isClose(trace.duration(of: .speechStartup), to: 0.292))
        #expect(isClose(trace.duration(of: .recording), to: 2.0))
        #expect(trace.duration(of: .transcription) == nil)
        #expect(isClose(trace.offsets[.stopRequested], to: 2.412))
    }

    @Test("lastReachedMilestone is the latest milestone other than finished")
    func lastReached() {
        var trace = makeTrace()
        #expect(trace.lastReachedMilestone == .hotkeyHandled)
        trace.mark(.hudArmed, at: at(50))
        trace.mark(.listening, at: at(400))
        #expect(trace.lastReachedMilestone == .listening)
        trace.finish(.cancelled, at: at(900))
        #expect(trace.lastReachedMilestone == .listening)
    }

    @Test("errorKind names the error without its payload")
    func errorKinds() {
        let speech = CaptureTrace.errorKind(of: LerroError.speechUnavailable("secret message"))
        #expect(speech == "speechUnavailable")
        #expect(!speech.contains("secret"))
        #expect(CaptureTrace.errorKind(of: LerroError.emptyTranscription) == "emptyTranscription")
        #expect(CaptureTrace.errorKind(of: CancellationError()) == "cancelled")
    }

    // MARK: CaptureTraceRecorder

    @Test("recorder ignores marks for another trace id")
    func recorderIgnoresStaleMarks() {
        var recorder = CaptureTraceRecorder()
        let current = makeTrace()
        recorder.begin(current)
        let result8 = !recorder.mark(.listening, id: UUID(), at: at(400))
        #expect(result8)
        #expect(recorder.current?.instants[.listening] == nil)
        let result9 = recorder.mark(.listening, id: current.id, at: at(400))
        #expect(result9)
        #expect(recorder.current?.instants[.listening] == at(400))
    }

    @Test("begin returns the previous trace only while it is open")
    func recorderBegin() {
        var recorder = CaptureTraceRecorder()
        let first = makeTrace()
        let second = makeTrace()
        let result10 = recorder.begin(first) == nil
        #expect(result10)
        let result11 = recorder.begin(second)?.id == first.id
        #expect(result11)
        #expect(recorder.current?.id == second.id)
        let result12 = recorder.finish(.completed, at: at(500)) != nil
        #expect(result12)
        let result13 = recorder.begin(makeTrace()) == nil
        #expect(result13)
    }

    @Test("recorder finish returns the trace once and clears current")
    func recorderFinish() throws {
        var recorder = CaptureTraceRecorder()
        let trace = makeTrace()
        recorder.begin(trace)
        let result14 = recorder.finish(.failed, errorKind: "speechUnavailable", at: at(700))
        let finished = try #require(result14)
        #expect(finished.id == trace.id)
        #expect(finished.outcome == .failed)
        #expect(finished.errorKind == "speechUnavailable")
        #expect(recorder.current == nil)
        let result15 = recorder.finish(.completed, at: at(800)) == nil
        #expect(result15)
    }

    @Test("setProcessingRoute ignores a stale id")
    func recorderRoute() {
        var recorder = CaptureTraceRecorder()
        let trace = makeTrace()
        recorder.begin(trace)
        recorder.setProcessingRoute(.remote, id: UUID())
        #expect(recorder.current?.processingRoute == nil)
        recorder.setProcessingRoute(.raw, id: trace.id)
        #expect(recorder.current?.processingRoute == .raw)
    }

    // MARK: Segments

    @Test("step segments follow the startup, analyzer and finish chains without crossing")
    func stepSegments() {
        let names = CaptureTraceSegment.steps.map(\.name)
        #expect(names.first == "hotkeyPressed>hotkeyHandled")
        #expect(names.contains("stopRequested>transcriptionFinished"))
        #expect(!names.contains("listening>stopRequested"))
        #expect(!names.contains("listening>firstAudioBuffer"))
        #expect(names.contains("audioEngineStarted>listening"))
        #expect(names.contains("audioEngineStarted>speechAssetsReserved"))
        #expect(!names.contains("analyzerPrepared>audioEngineStarted"))
        #expect(names.count == (CaptureMilestone.startupChain.count - 1)
            + (CaptureMilestone.analyzerChain.count - 1)
            + (CaptureMilestone.finishChain.count - 1))
        #expect(CaptureTraceSegment.summaries.count == 12)
    }

    // MARK: HistoryPhaseTimings

    private func decodeTimings(_ json: String) throws -> HistoryPhaseTimings {
        try JSONDecoder().decode(HistoryPhaseTimings.self, from: Data(json.utf8))
    }

    @Test("legacy phase timings decode with empty milestones and no outcome")
    func legacyTimings() throws {
        let timings = try decodeTimings(#"{"recording":1,"transcription":0.2,"processing":0.3,"delivery":0.1}"#)
        #expect(timings.recording == 1)
        #expect(timings.transcription == 0.2)
        #expect(timings.processing == 0.3)
        #expect(timings.delivery == 0.1)
        #expect(timings.milestones.isEmpty)
        #expect(timings.outcome == nil)
    }

    @Test("timings with milestones and outcome round trip")
    func timingsRoundTrip() throws {
        let timings = HistoryPhaseTimings(
            recording: 2,
            transcription: 0.3,
            processing: 0.4,
            delivery: 0.1,
            milestones: [.hotkeyPressed: 0, .listening: 0.412, .stopRequested: 2.412],
            outcome: .completedWithRawFallback
        )
        let data = try JSONEncoder().encode(timings)
        let decoded = try JSONDecoder().decode(HistoryPhaseTimings.self, from: data)
        #expect(decoded == timings)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let milestones = try #require(object["milestones"] as? [String: Double])
        #expect(milestones["listening"] == 0.412)
        #expect(object["outcome"] as? String == "completedWithRawFallback")
    }

    @Test("unknown milestone keys and outcomes are dropped on decode")
    func unknownKeysDropped() throws {
        let timings = try decodeTimings("""
        {"recording":1,"transcription":0.2,"processing":0.3,"delivery":0.1,
         "milestones":{"listening":0.4,"futureThing":1},"outcome":"weird"}
        """)
        #expect(timings.milestones == [.listening: 0.4])
        #expect(timings.outcome == nil)
    }

    @Test("stored analyzerContextSet milestones from older builds are dropped on decode")
    func removedMilestoneDropped() throws {
        let timings = try decodeTimings("""
        {"recording":1,"transcription":0.2,"processing":0.3,"delivery":0.1,
         "milestones":{"analyzerCreated":0.2,"analyzerContextSet":0.3,"analyzerPrepared":0.5}}
        """)
        #expect(timings.milestones == [.analyzerCreated: 0.2, .analyzerPrepared: 0.5])
    }

    @Test("empty milestones are omitted from the encoded JSON")
    func emptyMilestonesOmitted() throws {
        let timings = HistoryPhaseTimings(recording: 1, transcription: 0.2, processing: 0.3, delivery: 0.1)
        let data = try JSONEncoder().encode(timings)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["milestones"] == nil)
        #expect(object["outcome"] == nil)
    }

    @Test("init(trace:outcome:) derives the legacy phases and copies offsets")
    func timingsFromTrace() {
        var trace = makeTrace()
        trace.mark(.listening, at: at(400))
        trace.mark(.stopRequested, at: at(1_400))
        trace.mark(.transcriptionFinished, at: at(1_600))
        trace.mark(.processingFinished, at: at(1_900))
        trace.mark(.deliveryFinished, at: at(2_000))
        let timings = HistoryPhaseTimings(trace: trace, outcome: .completed)
        #expect(isClose(timings.recording, to: 1.0))
        #expect(isClose(timings.transcription, to: 0.2))
        #expect(isClose(timings.processing, to: 0.3))
        #expect(isClose(timings.delivery, to: 0.1))
        #expect(timings.outcome == .completed)
        #expect(isClose(timings.milestones[.listening], to: 0.4))
        #expect(isClose(timings.milestones[.deliveryFinished], to: 2.0))
    }

    @Test("init(trace:outcome:) uses zero for phases that were not reached")
    func timingsFromEarlyTrace() {
        var trace = makeTrace()
        trace.mark(.listening, at: at(400))
        let timings = HistoryPhaseTimings(trace: trace, outcome: .cancelled)
        #expect(timings.recording == 0)
        #expect(timings.transcription == 0)
        #expect(timings.processing == 0)
        #expect(timings.delivery == 0)
    }

    @Test("duration(of:) uses the stored milestone offsets")
    func timingsDuration() throws {
        let timings = try decodeTimings("""
        {"recording":1,"transcription":0.2,"processing":0.3,"delivery":0.1,
         "milestones":{"hotkeyPressed":0,"listening":0.412,"stopRequested":2.412}}
        """)
        #expect(isClose(timings.duration(of: .readyToSpeak), to: 0.412))
        #expect(isClose(timings.duration(of: .recording), to: 2.0))
        #expect(timings.duration(of: .transcription) == nil)
    }

    // MARK: HistoryEntry and HotkeyTrigger

    @Test("a history entry with legacy phase timings still decodes")
    func legacyHistoryEntry() throws {
        let json = """
        {"id":"00000000-0000-0000-0000-000000000001","createdAt":"2026-10-16T17:01:35Z",
         "mode":"dictation","rawText":"a","finalText":"b","duration":3,"applicationName":"Notes",
         "status":"completed","wasEnhanced":false,
         "phaseTimings":{"recording":1,"transcription":0.2,"processing":0.3,"delivery":0.1}}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entry = try decoder.decode(HistoryEntry.self, from: Data(json.utf8))
        let timings = try #require(entry.phaseTimings)
        #expect(timings.recording == 1)
        #expect(timings.milestones.isEmpty)
        #expect(timings.outcome == nil)
    }

    @Test("hotkey trigger equality ignores pressedAt")
    func triggerEquality() {
        let first = HotkeyTrigger(
            action: .dictate, activation: .hold, phase: .began, definitionID: "d", pressedAt: at(0)
        )
        let second = HotkeyTrigger(
            action: .dictate, activation: .hold, phase: .began, definitionID: "d", pressedAt: at(500)
        )
        let withoutInstant = HotkeyTrigger(action: .dictate, activation: .hold, phase: .began, definitionID: "d")
        let other = HotkeyTrigger(action: .translate, activation: .hold, phase: .began, definitionID: "d")
        #expect(first == second)
        #expect(first == withoutInstant)
        #expect(first != other)
    }
}

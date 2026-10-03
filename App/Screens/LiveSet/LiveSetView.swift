import SwiftUI
import Contracts
import DesignSystem
import LiveSet

/// Runs a series of sets for one exercise: live view, then the summary between sets.
struct LiveSetFlow: View {
    let exercise: ExerciseItem
    let spec: TempoSpec
    let totalSets: Int
    let onClose: () -> Void

    @State private var setIndex = 1

    var body: some View {
        LiveSetView(exercise: exercise, spec: spec, setIndex: setIndex, totalSets: totalSets,
                    onNextSet: { setIndex += 1 }, onClose: onClose)
            .id(setIndex)
    }
}

/// One live set. Owner: Michał.
struct LiveSetView: View {
    let totalSets: Int
    let onNextSet: () -> Void
    let onClose: () -> Void
    /// Set when a workout runner drives the sets: it gets the result instead of this view's own summary screen.
    var onFinished: ((SetSummary) -> Void)?
    /// Set by the workout runner: a way to ask the coach before the set starts.
    var onAskCoach: (() -> Void)?

    @Environment(AppStore.self) private var store
    @State private var session: LiveSetSession
    /// Numbers, colours and pose export for checking the analysis on a real phone.
    @State private var diagnostics = false

    init(exercise: ExerciseItem, spec: TempoSpec, setIndex: Int, totalSets: Int,
         onNextSet: @escaping () -> Void, onClose: @escaping () -> Void,
         onFinished: ((SetSummary) -> Void)? = nil, onAskCoach: (() -> Void)? = nil) {
        self.totalSets = totalSets
        self.onNextSet = onNextSet
        self.onClose = onClose
        self.onFinished = onFinished
        self.onAskCoach = onAskCoach
        _session = State(initialValue: LiveSetSession(exercise: exercise, spec: spec, setIndex: setIndex))
    }

    private var engine: LiveSetEngine { session.engine }

    var body: some View {
        ZStack {
            if engine.stage == .summary, let summary = engine.summary {
                if let onFinished {
                    // The runner records the set and shows its own screen.
                    ProgressView().tint(FormaColor.voltText).onAppear { onFinished(summary) }
                } else {
                    SetSummaryView(summary: summary, exerciseName: session.exercise.name, totalSets: totalSets,
                                   onNextSet: onNextSet, onClose: onClose)
                        .onAppear { store.recordSet(summary) }
                }
            } else {
                live
            }
        }
        .onAppear {
            #if os(iOS)
            UIApplication.shared.isIdleTimerDisabled = true
            #endif
            session.start()
        }
        .onDisappear {
            #if os(iOS)
            UIApplication.shared.isIdleTimerDisabled = false
            #endif
            session.stop()
        }
    }

    // MARK: - Live

    private var live: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                topBar
                if diagnostics { DiagnosticsHUD(engine: engine, kind: session.kind).padding(.top, FormaSpacing.s) }
                Spacer()
                panel
            }
            .padding(.horizontal, FormaSpacing.screen)
            .padding(.bottom, FormaSpacing.l)
        }
        .background(Color.black)
    }

    @ViewBuilder
    private var background: some View {
        GeometryReader { geo in
            // With the camera the video fills the screen; in the simulation keep the skeleton above the panel.
            let reserve: CGFloat = session.source == .simulation ? 250 : 0
            let video = Self.fittedRect(aspect: 9.0 / 16.0, in: CGSize(width: geo.size.width, height: geo.size.height - reserve))
            ZStack {
                if session.source == .camera {
                    #if os(iOS)
                    CameraPreview(session: session.camera.session, revision: session.cameraRevision)
                    #endif
                } else {
                    AmbientBackground()
                }
                SkeletonOverlay(frame: engine.latestFrame, debug: diagnostics)
                    // The camera mirrors the front picture itself; the simulated skeleton is mirrored to match.
                    .scaleEffect(x: session.source == .simulation && session.isFrontCamera ? -1 : 1, y: 1)
                    .frame(width: video.width, height: video.height)
                    .position(x: video.midX, y: video.midY)
                LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
                    .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
    }

    private static func fittedRect(aspect: CGFloat, in size: CGSize) -> CGRect {
        var width = size.width
        var height = width / aspect
        if height > size.height {
            height = size.height
            width = height * aspect
        }
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
    }

    private var topBar: some View {
        HStack(spacing: FormaSpacing.m) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .glassCapsule(interactive: true)
            }
            .accessibilityLabel("Zamknij")

            VStack(alignment: .leading, spacing: 2) {
                Text(session.exercise.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Seria \(session.setIndex)/\(totalSets) · \(session.spec.label)\(session.source == .simulation ? " · symulacja" : "")")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            if engine.stage == .active {
                Button {
                    engine.finish()
                } label: {
                    Text("Zakończ")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 14)
                        .frame(height: 44)
                        .glassCapsule(interactive: true)
                }
                .accessibilityLabel("Zakończ serię")
            }
            if session.canFlipCamera {
                Button { session.flipCamera() } label: {
                    Image(systemName: "camera.rotate")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .glassCapsule(interactive: true)
                }
                .accessibilityLabel(session.isFrontCamera ? "Przełącz na tylną kamerę" : "Przełącz na przednią kamerę")
            }
            Button {
                diagnostics.toggle()
                engine.recordsFrames = diagnostics
            } label: {
                Image(systemName: diagnostics ? "ladybug.fill" : "ladybug")
                    .foregroundStyle(diagnostics ? FormaColor.volt : .white)
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("Diagnostyka")
            Image(systemName: engine.headphonesConnected ? "headphones" : "speaker.wave.2.fill")
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .accessibilityLabel(engine.headphonesConnected ? "Słuchawki podłączone" : "Dźwięk z głośnika")
        }
        .padding(.top, FormaSpacing.s)
    }

    // MARK: - Panels

    @ViewBuilder
    private var panel: some View {
        VStack(alignment: .leading, spacing: FormaSpacing.m) {
            if let error = session.cameraError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .formaStyle(.subheadline)
                    .foregroundStyle(FormaColor.moderateText)
            }
            switch engine.stage {
            case .framing: framingPanel
            case .calibrating(let progress): calibratingPanel(progress)
            case .active: activePanel
            case .summary: EmptyView()
            }
        }
        .padding(FormaSpacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var framingPanel: some View {
        VStack(alignment: .leading, spacing: FormaSpacing.m) {
            Text("Ustaw telefon").formaStyle(.title2).foregroundStyle(FormaColor.ink)
            Text(session.kind.setupHint)
                .formaStyle(.subheadline).foregroundStyle(FormaColor.ink2)
            ForEach(engine.framing.checks) { check in
                Label(check.label, systemImage: check.passed ? "checkmark.circle.fill" : "circle.dashed")
                    .formaStyle(.subheadline)
                    .foregroundStyle(check.passed ? FormaColor.goText : FormaColor.ink2)
            }
            if let hint = engine.framing.hint {
                Label(hint, systemImage: "arrow.right.circle.fill")
                    .formaStyle(.headline)
                    .foregroundStyle(FormaColor.moderateText)
            }
            Label(engine.headphonesConnected ? "Słuchawki podłączone" : "Brak słuchawek: dźwięk z głośnika",
                  systemImage: engine.headphonesConnected ? "headphones" : "speaker.wave.2.fill")
                .formaStyle(.footnote).foregroundStyle(FormaColor.ink3)
            Label(session.isFrontCamera ? "Kamera przednia: widzisz siebie na ekranie (przycisk w prawym górnym rogu przełącza)"
                                        : "Kamera tylna (przycisk w prawym górnym rogu przełącza na przednią)",
                  systemImage: "camera")
                .formaStyle(.footnote).foregroundStyle(FormaColor.ink3)
            Button {
                engine.startCalibrationNow()
            } label: {
                Text("Start bez czekania").frame(maxWidth: .infinity)
            }
            .buttonStyle(.formaGlass)
            if let onAskCoach {
                Button(action: onAskCoach) {
                    Label("Zapytaj trenera", systemImage: "bubble.left.and.text.bubble.right").frame(maxWidth: .infinity)
                }
                .buttonStyle(.formaGlass)
            }
        }
    }

    private func calibratingPanel(_ progress: Double) -> some View {
        HStack(spacing: FormaSpacing.l) {
            ProgressRing(progress: progress, lineWidth: 8) {
                Image(systemName: session.kind == .pullup ? "figure.climbing" : session.kind == .pushup ? "figure.strengthtraining.functional" : "figure.stand").font(.system(size: 22)).foregroundStyle(FormaColor.ink)
            }
            .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(session.kind.calibrationTitle).formaStyle(.headline).foregroundStyle(FormaColor.ink)
                Text("Kalibruję pozycję wyjściową.").formaStyle(.subheadline).foregroundStyle(FormaColor.ink2)
            }
        }
    }

    private var activePanel: some View {
        VStack(alignment: .leading, spacing: FormaSpacing.m) {
            HStack(alignment: .center, spacing: FormaSpacing.xl) {
                VStack(alignment: .leading, spacing: 0) {
                    NumberText("\(engine.reps.count)", size: 72)
                    Text(engine.reps.count == 1 ? "powtórzenie" : (2...4).contains(engine.reps.count % 10) && !(12...14).contains(engine.reps.count % 100) ? "powtórzenia" : "powtórzeń")
                        .formaStyle(.caption).foregroundStyle(FormaColor.ink3)
                    if let score = engine.liveTechniqueScore {
                        Text("\(score)% poprawnej techniki").formaStyle(.caption).foregroundStyle(FormaColor.ink3)
                    }
                }
                Spacer()
                phaseTimer
            }
            if let cue = engine.lastCue {
                Label(cue, systemImage: "speaker.wave.2.fill")
                    .formaStyle(.headline)
                    .foregroundStyle(FormaColor.voltText)
                    .lineLimit(1)
            }
        }
    }

    private var phaseTimer: some View {
        TimelineView(.animation(minimumInterval: 0.1)) { context in
            let phase = engine.currentPhase
            let target = phase.map { CuePlanner.duration(of: $0, in: session.spec) } ?? 0
            let elapsed = max(0, engine.phaseStartedAt.map { context.date.timeIntervalSince($0) } ?? 0)
            ProgressRing(progress: phase == nil || target == 0 ? 0 : elapsed / target, lineWidth: 10,
                         color: phase == .eccentric ? FormaColor.ember : FormaColor.volt) {
                VStack(spacing: 2) {
                    Text(phase?.title ?? "Gotowy")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(FormaColor.ink)
                    if phase != nil {
                        Text(String(format: "%.1f s", locale: Locale(identifier: "pl_PL"), elapsed))
                            .font(.formaNumber(15))
                            .monospacedDigit()
                            .foregroundStyle(FormaColor.ink2)
                    }
                }
            }
        }
        .frame(width: 96, height: 96)
    }
}

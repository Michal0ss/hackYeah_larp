import SwiftUI
import Contracts
import DesignSystem
import LiveSet

/// Panel for testing the live analysis on a real phone: what the camera pipeline sees, numbers behind the rules,
/// and a way to export the recorded poses (joint numbers only, never video) as test fixtures for Bartek.
struct DiagnosticsHUD: View {
    let engine: LiveSetEngine
    var kind: MovementKind = .squat
    @State private var exportItem: ExportFile?

    private var d: PoseDiagnostics { PoseDiagnostics.measure(engine.latestFrame) }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            line([("fps", String(format: "%.0f", engine.framesPerSecond), engine.framesPerSecond >= 15),
                  ("stawy", "\(d.jointCount)/15", d.jointCount >= 11),
                  ("pewność", Self.f(d.meanConfidence, 2), d.meanConfidence >= 0.5)])
            switch kind {
            case .squat:
                line([("kolano", d.kneeAngle.map { Self.f($0, 0) + "°" } ?? "—", d.kneeAngle != nil),
                      ("tułów", d.torsoLean.map { Self.f($0, 0) + "°" } ?? "—", (d.torsoLean ?? 99) <= 45),
                      ("bio<kol", d.hipBelowKnee.map { $0 ? "tak" : "nie" } ?? "—", d.hipBelowKnee != nil)])
            case .pushup:
                line([("łokieć", d.elbowAngle.map { Self.f($0, 0) + "°" } ?? "—", d.elbowAngle != nil),
                      ("linia ciała", d.bodyLineAngle.map { Self.f($0, 0) + "°" } ?? "—", (d.bodyLineAngle ?? 0) >= 160)])
            case .dip:
                line([("łokieć", d.elbowAngle.map { Self.f($0, 0) + "°" } ?? "—", d.elbowAngle != nil),
                      ("tułów", d.torsoLean.map { Self.f($0, 0) + "°" } ?? "—", d.torsoLean != nil)])
            case .pullup:
                line([("łokieć", d.elbowAngle.map { Self.f($0, 0) + "°" } ?? "—", d.elbowAngle != nil),
                      ("nos nad rękami", d.noseAboveWrists.map { $0 ? "tak" : "nie" } ?? "—", d.noseAboveWrists != nil)])
            }
            line([("sylwetka", d.bodyHeight.map { Self.f($0, 2) } ?? "—", (0.45...0.95).contains(d.bodyHeight ?? 0)),
                  ("barki", d.shoulderRatio.map { Self.f($0, 2) } ?? "—", kind == .pullup || (d.shoulderRatio ?? 0) <= 0.5),
                  ("noga", d.side ?? "—", d.side != nil)])
            line([("głęb.", engine.latestDepth.map { Self.f($0, 2) } ?? "—", engine.latestDepth != nil),
                  ("v", Self.f(engine.trackerVelocity, 2), true),
                  ("powt.", "\(engine.reps.count)", true),
                  ("faza", engine.currentPhase?.title ?? "—", true)])
            Text("etap: " + Self.stageText(engine.stage) + (d.missing.isEmpty ? "" : " · brak: " + d.missing.joined(separator: ",")))
                .foregroundStyle(d.missing.isEmpty ? .white.opacity(0.7) : .orange)
                .lineLimit(2)
            HStack {
                Text("klatki: \(engine.recordedFrames.count)").foregroundStyle(.white.opacity(0.7))
                Spacer()
                Button("Wyślij pozy (JSON)") { prepareExport() }
                    .disabled(engine.recordedFrames.isEmpty)
            }
        }
        .font(.system(size: 10, design: .monospaced))
        .foregroundStyle(.white)
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .sheet(item: $exportItem) { item in ActivityView(url: item.url) }
    }

    private func line(_ items: [(String, String, Bool)]) -> some View {
        HStack(spacing: 10) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 3) {
                    Text(item.0).foregroundStyle(.white.opacity(0.6))
                    Text(item.1).foregroundStyle(item.2 ? Color.green : Color.orange)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func prepareExport() {
        guard let data = engine.recordedPoseJSON() else { return }
        let name = "poza-\(engine.exerciseId)-\(Int(Date().timeIntervalSince1970)).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? data.write(to: url, options: .atomic)
        exportItem = ExportFile(url: url)
    }

    private static func f(_ value: Double, _ digits: Int) -> String { String(format: "%.\(digits)f", value) }

    private static func stageText(_ stage: LiveSetEngine.Stage) -> String {
        switch stage {
        case .framing: return "kadr"
        case .calibrating(let p): return "kalibracja \(Int(p * 100))%"
        case .active: return "aktywna"
        case .summary: return "podsumowanie"
        }
    }
}

struct ExportFile: Identifiable {
    let id = UUID()
    let url: URL
}

#if os(iOS)
struct ActivityView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
#endif

import SwiftUI
import PhotosUI
import DesignSystem

/// Step 3: record a new clip or pick an existing one from the gallery.
struct CaptureStepView: View {
    let model: AnalysisModel

    @State private var showingCamera = false
    @State private var photosItem: PhotosPickerItem?
    @State private var isImportingFromGallery = false
    @State private var importError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: FormaSpacing.l) {
            Text("Nagraj albo wybierz film")
                .formaStyle(.title)
                .foregroundStyle(FormaColor.ink)
            Text("Przysiady z boku, co najmniej 3 powtórzenia.")
                .formaStyle(.callout)
                .foregroundStyle(FormaColor.ink2)

            VStack(spacing: FormaSpacing.m) {
                if MovieCapturePicker.isAvailable {
                    Button {
                        showingCamera = true
                    } label: {
                        Label("Nagraj teraz", systemImage: "video.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.formaPrimary)
                } else {
                    Text("Nagrywanie kamerą działa tylko na fizycznym iPhonie — w symulatorze wybierz film z galerii.")
                        .formaStyle(.footnote)
                        .foregroundStyle(FormaColor.ink3)
                        .padding(FormaSpacing.l)
                        .glassCard()
                }

                PhotosPicker(selection: $photosItem, matching: .videos) {
                    Label("Wybierz z galerii", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.formaGlass)
                .disabled(isImportingFromGallery)
            }

            if isImportingFromGallery {
                HStack(spacing: FormaSpacing.s) {
                    ProgressView()
                    Text("Wczytywanie filmu…").formaStyle(.footnote).foregroundStyle(FormaColor.ink3)
                }
            }
            if let importError {
                Text(importError).formaStyle(.footnote).foregroundStyle(FormaColor.ember)
            }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            MovieCapturePicker { url in
                showingCamera = false
                if let url { model.use(video: url) }
            }
            .ignoresSafeArea()
        }
        .onChange(of: photosItem) { _, newValue in
            guard let newValue else { return }
            Task { await importFromGallery(newValue) }
        }
    }

    private func importFromGallery(_ item: PhotosPickerItem) async {
        isImportingFromGallery = true
        importError = nil
        defer { isImportingFromGallery = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                importError = "Nie udało się wczytać filmu z galerii."
                return
            }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
            try data.write(to: url)
            model.use(video: url)
        } catch {
            importError = "Nie udało się wczytać filmu z galerii."
        }
    }
}

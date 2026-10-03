import SwiftUI
import PhotosUI
import CoreTransferable
import UniformTypeIdentifiers
import DesignSystem

/// Copies the picked video to our own temp file instead of loading it as `Data` — a long
/// recording loaded whole into memory risked crashing the app.
private struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
            try FileManager.default.copyItem(at: received.file, to: copy)
            return Self(url: copy)
        }
    }
}

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
            Text("\(model.kind.title) z boku, co najmniej 3 powtórzenia.")
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
            // Forget the selection, so picking the same clip again (after a retry) fires onChange again.
            defer { photosItem = nil }
            guard let movie = try await item.loadTransferable(type: PickedMovie.self) else {
                importError = "Nie udało się wczytać filmu z galerii."
                return
            }
            model.use(video: movie.url)
        } catch {
            importError = "Nie udało się wczytać filmu z galerii."
        }
    }
}

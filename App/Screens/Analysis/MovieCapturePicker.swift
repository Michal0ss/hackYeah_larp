import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Records a short movie with the camera (`UIImagePickerController`; `PhotosPicker` doesn't offer
/// capture). Not available in the Simulator — callers should check `isAvailable` first.
struct MovieCapturePicker: UIViewControllerRepresentable {
    let onFinish: (URL?) -> Void

    static let isAvailable: Bool = UIImagePickerController.isSourceTypeAvailable(.camera)

    /// A longer clip only makes the reading slower; a set is a few repetitions.
    static let maxDuration: TimeInterval = 60

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .video
        picker.cameraDevice = .rear
        picker.mediaTypes = [UTType.movie.identifier]
        picker.videoQuality = .typeMedium
        picker.videoMaximumDuration = Self.maxDuration
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (URL?) -> Void
        init(onFinish: @escaping (URL?) -> Void) { self.onFinish = onFinish }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onFinish(info[.mediaURL] as? URL)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(nil)
        }
    }
}

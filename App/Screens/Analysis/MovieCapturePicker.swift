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
        // The media types come first: asking for the video mode while the picker still offers only photos is an
        // exception ("cameraCaptureMode 1 not available because mediaTypes does contain public.movie") and kills the app.
        picker.mediaTypes = [UTType.movie.identifier]
        if UIImagePickerController.availableCaptureModes(for: .rear)?.contains(NSNumber(value: UIImagePickerController.CameraCaptureMode.video.rawValue)) == true {
            picker.cameraCaptureMode = .video
        }
        if UIImagePickerController.isCameraDeviceAvailable(.rear) { picker.cameraDevice = .rear }
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

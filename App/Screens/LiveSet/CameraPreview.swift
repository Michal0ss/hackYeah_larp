import SwiftUI
import AVFoundation
import LiveSet

#if os(iOS)
/// The camera picture, aspect-fit so the skeleton overlay lines up exactly. It shows the upright frames that
/// `CameraPoseSource` hands over (the very pictures Vision analyses), not an `AVCaptureVideoPreviewLayer`: the preview
/// layer's own rotation came out turned by 90 degrees on the selfie camera and could not be relied on.
struct CameraPreview: UIViewRepresentable {
    let camera: CameraPoseSource

    final class PreviewView: UIView {
        private let lock = NSLock()
        private var pending: CGImage?
        private var scheduled = false

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .black
            layer.contentsGravity = .resizeAspect
            layer.masksToBounds = true
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        /// Called from the camera queue for every frame; only the newest picture is kept for the next screen refresh.
        func show(_ image: CGImage) {
            lock.lock()
            pending = image
            let alreadyScheduled = scheduled
            scheduled = true
            lock.unlock()
            guard !alreadyScheduled else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.lock.lock()
                let image = self.pending
                self.pending = nil
                self.scheduled = false
                self.lock.unlock()
                self.layer.contents = image
            }
        }
    }

    /// Lets go of the camera when the view goes away, so no pictures are made for nobody.
    final class Coordinator {
        let camera: CameraPoseSource
        init(camera: CameraPoseSource) { self.camera = camera }
    }

    func makeCoordinator() -> Coordinator { Coordinator(camera: camera) }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        camera.onPreviewImage = { [weak view] image in view?.show(image) }
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    static func dismantleUIView(_ uiView: PreviewView, coordinator: Coordinator) {
        coordinator.camera.onPreviewImage = nil
    }
}
#endif

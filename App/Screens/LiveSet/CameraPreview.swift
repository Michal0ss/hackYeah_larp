import SwiftUI
import AVFoundation

#if os(iOS)
/// Camera image. `videoGravity` is aspect-fit so the skeleton overlay lines up exactly.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    /// Changes when the camera was switched: the new connection of the preview layer needs its rotation again.
    var revision = 0

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        /// The preview connection only exists once the capture session has its input, which happens after this view
        /// is created. Set the portrait rotation whenever it is available (layout runs again when the session starts).
        override func layoutSubviews() {
            super.layoutSubviews()
            applyRotation()
        }

        private var watchdog: Timer?

        func applyRotation() {
            if let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(90),
               connection.videoRotationAngle != 90 {
                connection.videoRotationAngle = 90
            }
        }

        /// The preview connection is replaced whenever the camera input is (the selfie camera, a switch, an
        /// interruption) and nothing tells the view. While the view is on screen it is checked twice a second, so the
        /// picture never stays turned by 90 degrees.
        override func didMoveToWindow() {
            super.didMoveToWindow()
            watchdog?.invalidate()
            watchdog = nil
            guard window != nil else { return }
            watchdog = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.applyRotation() }
        }

        deinit { watchdog?.invalidate() }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.setNeedsLayout()
        // A switch finishes on the capture queue a moment after the tap: apply the rotation once it has.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { uiView.applyRotation() }
    }
}
#endif

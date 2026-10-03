import SwiftUI
import AVFoundation

#if os(iOS)
/// Camera image. `videoGravity` is aspect-fit so the skeleton overlay lines up exactly.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        /// The preview connection only exists once the capture session has its input, which happens after this view
        /// is created. Set the portrait rotation whenever it is available (layout runs again when the session starts).
        override func layoutSubviews() {
            super.layoutSubviews()
            if let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(90),
               connection.videoRotationAngle != 90 {
                connection.videoRotationAngle = 90
            }
        }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) { uiView.setNeedsLayout() }
}
#endif

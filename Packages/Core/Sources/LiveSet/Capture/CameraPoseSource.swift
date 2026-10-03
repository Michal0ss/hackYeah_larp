#if os(iOS)
import Foundation
import AVFoundation
import Vision
import Contracts

/// Live camera -> body pose (Apple Vision) -> `PoseFrame` stream. Nothing is recorded or stored:
/// every video frame is analysed and dropped. Real device only (the simulator has no camera).
public final class CameraPoseSource: NSObject, @unchecked Sendable {
    public enum Position { case back, front }
    public enum CameraError: Error { case denied, unavailable }

    /// Use this for the on-screen preview.
    public let session = AVCaptureSession()

    private let queue = DispatchQueue(label: "forma.camera.pose", qos: .userInitiated)
    private let output = AVCaptureVideoDataOutput()
    private let request = VNDetectHumanBodyPoseRequest()
    private var continuation: AsyncStream<PoseFrame>.Continuation?
    private var firstTimestamp: Double?
    private var configured = false

    private static let jointMap: [(VNHumanBodyPoseObservation.JointName, JointName)] = [
        (.nose, .nose), (.neck, .neck),
        (.leftShoulder, .leftShoulder), (.rightShoulder, .rightShoulder),
        (.leftElbow, .leftElbow), (.rightElbow, .rightElbow),
        (.leftWrist, .leftWrist), (.rightWrist, .rightWrist),
        (.root, .root),
        (.leftHip, .leftHip), (.rightHip, .rightHip),
        (.leftKnee, .leftKnee), (.rightKnee, .rightKnee),
        (.leftAnkle, .leftAnkle), (.rightAnkle, .rightAnkle),
    ]

    public override init() {
        super.init()
    }

    /// Asks for permission, starts the camera and returns the frames. Ends when the stream is cancelled.
    public func frames(position: Position = .back) async throws -> AsyncStream<PoseFrame> {
        guard await AVCaptureDevice.requestAccess(for: .video) else { throw CameraError.denied }
        if !configured { try configure(position: position) }
        firstTimestamp = nil
        let stream = AsyncStream<PoseFrame>(bufferingPolicy: .bufferingNewest(4)) { continuation in
            self.continuation = continuation
            continuation.onTermination = { [weak self] _ in self?.stop() }
        }
        queue.async { [session] in session.startRunning() }
        return stream
    }

    public func stop() {
        continuation?.finish()
        continuation = nil
        queue.async { [session] in if session.isRunning { session.stopRunning() } }
    }

    private func configure(position: Position) throws {
        let devicePosition: AVCaptureDevice.Position = position == .back ? .back : .front
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: devicePosition),
              let input = try? AVCaptureDeviceInput(device: device) else { throw CameraError.unavailable }

        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .hd1280x720
        guard session.canAddInput(input) else { throw CameraError.unavailable }
        session.addInput(input)

        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else { throw CameraError.unavailable }
        session.addOutput(output)

        // Portrait, upright buffers, so Vision coordinates match what the user sees.
        if let connection = output.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
            if position == .front, connection.isVideoMirroringSupported { connection.isVideoMirrored = true }
        }
        configured = true
    }
}

extension CameraPoseSource: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer), let continuation else { return }
        let stamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        let first = firstTimestamp ?? stamp
        firstTimestamp = first

        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up, options: [:])
        try? handler.perform([request])
        let time = stamp - first

        // Several people: take the one with the highest total joint confidence.
        let best = (request.results ?? []).max { score($0) < score($1) }
        continuation.yield(PoseFrame(time: time, joints: best.map(joints(of:)) ?? []))
    }

    private func score(_ observation: VNHumanBodyPoseObservation) -> Float {
        guard let points = try? observation.recognizedPoints(.all) else { return 0 }
        return points.values.reduce(0) { $0 + $1.confidence }
    }

    private func joints(of observation: VNHumanBodyPoseObservation) -> [Contracts.Joint] {
        Self.jointMap.compactMap { vision, ours in
            guard let point = try? observation.recognizedPoint(vision), point.confidence > 0.05 else { return nil }
            // Vision: origin bottom-left. Ours: origin top-left.
            return Contracts.Joint(name: ours, x: Double(point.location.x), y: 1 - Double(point.location.y),
                         confidence: Double(point.confidence))
        }
    }
}
#endif

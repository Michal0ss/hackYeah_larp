#if os(iOS)
import Foundation
import AVFoundation
import Vision
import Contracts
import CoreImage

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
    /// The camera in use and its input (changed only on `queue`, or before the first frame while configuring).
    private var position: Position = .back
    private var input: AVCaptureDeviceInput?
    /// Called on the main queue after the camera was switched.
    public var onSwitched: (@Sendable () -> Void)?
    /// Every frame as an upright picture (portrait, the selfie camera mirrored like a mirror), on the camera queue.
    /// The preview shows exactly this, the same picture Vision analyses, so what is drawn and what is measured can
    /// never be turned against each other.
    public var onPreviewImage: (@Sendable (CGImage) -> Void)?
    private let imageContext = CIContext()

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
        else if position != self.position { try queue.sync { try swapInput(to: position) } }
        firstTimestamp = nil
        let stream = AsyncStream<PoseFrame>(bufferingPolicy: .bufferingNewest(4)) { continuation in
            self.continuation = continuation
            continuation.onTermination = { [weak self] _ in self?.stop() }
        }
        queue.async { [session] in session.startRunning() }
        return stream
    }

    /// Switches between the back and the front camera while the session runs. The frame stream keeps going, so the
    /// time of the frames stays continuous. If the other camera cannot be used, the current one stays.
    public func switchCamera(to position: Position) {
        queue.async { [weak self] in
            guard let self, self.configured, position != self.position else { return }
            do { try self.swapInput(to: position) } catch { return }
            DispatchQueue.main.async { self.onSwitched?() }
        }
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
        self.input = input
        self.position = position

        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else { throw CameraError.unavailable }
        session.addOutput(output)

        applyConnectionSettings()
        configured = true
    }

    /// Replaces the camera input of the session (the output and the running state stay as they are).
    private func swapInput(to position: Position) throws {
        let devicePosition: AVCaptureDevice.Position = position == .back ? .back : .front
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: devicePosition),
              let newInput = try? AVCaptureDeviceInput(device: device) else { throw CameraError.unavailable }

        session.beginConfiguration()
        if let current = input { session.removeInput(current) }
        guard session.canAddInput(newInput) else {
            if let current = input, session.canAddInput(current) { session.addInput(current) }  // keep what worked
            session.commitConfiguration()
            throw CameraError.unavailable
        }
        session.addInput(newInput)
        input = newInput
        self.position = position
        session.commitConfiguration()
        // The new input brought a new connection to the output.
        applyConnectionSettings()
    }

    /// The output delivers the picture exactly as the sensor made it (no rotation, no mirroring by the connection).
    /// Turning it upright is done here, from the position of the camera, so it does not depend on what the capture
    /// connection decided after an input swap (the selfie camera came out turned by 90 degrees that way).
    private func applyConnectionSettings() {
        guard let connection = output.connection(with: .video) else { return }
        Self.neutral(connection)
    }

    private static func neutral(_ connection: AVCaptureConnection) {
        if connection.isVideoMirroringSupported {
            if connection.automaticallyAdjustsVideoMirroring { connection.automaticallyAdjustsVideoMirroring = false }
            if connection.isVideoMirrored { connection.isVideoMirrored = false }
        }
        if connection.isVideoRotationAngleSupported(0), connection.videoRotationAngle != 0 { connection.videoRotationAngle = 0 }
    }

    /// How to turn a sensor picture into an upright portrait one. The sensors of an iPhone are landscape: held upright,
    /// the back camera needs `.right` and the front camera `.leftMirrored` (a selfie is mirrored). A buffer that is
    /// already portrait only needs the mirror for the front camera.
    static func orientation(width: Int, height: Int, position: Position) -> CGImagePropertyOrientation {
        let landscape = width >= height
        switch (position, landscape) {
        case (.back, true): return .right
        case (.front, true): return .leftMirrored
        case (.back, false): return .up
        case (.front, false): return .upMirrored
        }
    }
}

extension CameraPoseSource: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer), let continuation else { return }
        Self.neutral(connection)
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let orientation = Self.orientation(width: width, height: height, position: position)
        if let onPreviewImage {
            let upright = CIImage(cvPixelBuffer: buffer).oriented(orientation)
            if let image = imageContext.createCGImage(upright, from: upright.extent) { onPreviewImage(image) }
        }
        let stamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        let first = firstTimestamp ?? stamp
        firstTimestamp = first

        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: orientation, options: [:])
        try? handler.perform([request])
        let time = stamp - first

        // Several people: take the one with the highest total joint confidence.
        let best = (request.results ?? []).max { score($0) < score($1) }
        // Width over height of the upright picture.
        let aspect = width > 0 && height > 0 ? Double(min(width, height)) / Double(max(width, height)) : nil
        continuation.yield(PoseFrame(time: time, joints: best.map(joints(of:)) ?? [], aspect: aspect))
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

import AVFoundation
import Contracts
import CoreImage
import Foundation
import Vision

/// What the extractor reports while it reads a clip: how far it is, the pose found in the frame it just did, and (on
/// every other frame) a small upright still of that frame, so the screen can show the skeleton over the video like the
/// live set does. The still stays in memory and is never written anywhere; the video does not leave the phone.
public struct ClipExtractionProgress: @unchecked Sendable {
    /// 0...1 of the clip's duration.
    public var fraction: Double
    public var frame: PoseFrame
    public var image: CGImage?
    /// Frames analysed so far.
    public var framesDone: Int
}

/// Reads a squat video file frame by frame and runs Apple Vision body pose detection on each one.
/// File-based counterpart to `LiveSet.CameraPoseSource` (live camera): same joints, same `PoseFrame`
/// contract, but everything is read up front with `AVAssetReader` instead of streamed from a capture session.
public enum VisionPoseExtractor {
    public enum ExtractionError: Error, Equatable {
        case noVideoTrack
        case readerFailedToStart
        case readerFailed
    }

    /// Vision confidence below which a joint is left out of the frame.
    public static var minJointConfidence: Float = 0.05

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

    /// Frames are analysed at about this many per second: a 60 or 240 fps clip is thinned out, because the repetitions
    /// of an exercise are slow and Vision would otherwise need minutes for a short clip.
    public static var maxAnalysedFps = 30.0

    /// Width in pixels of the stills sent to `progress`.
    public static var previewWidth: CGFloat = 360

    private static let imageContext = CIContext()

    /// Runs pose detection on every frame of `url`. `time` in the returned frames is seconds from the
    /// first frame, regardless of where the source video's own timestamps start.
    public static func extract(from url: URL) async throws -> [PoseFrame] {
        try await extract(from: url, progress: nil)
    }

    /// The same, reporting progress (called on the extracting thread, not the main actor). Cancelling the task stops
    /// the reading.
    public static func extract(from url: URL, progress: (@Sendable (ClipExtractionProgress) -> Void)?) async throws -> [PoseFrame] {
        let asset = AVURLAsset(url: url)
        let duration = (try? await asset.load(.duration).seconds) ?? 0
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw ExtractionError.noVideoTrack
        }
        // iPhone video is stored landscape with the actual orientation in the track's transform;
        // without this Vision sees a sideways person and poses come out wrong or empty.
        let transform = try await track.load(.preferredTransform)
        let orientation = cgOrientation(for: transform)

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw ExtractionError.readerFailedToStart }
        reader.add(output)
        guard reader.startReading() else { throw ExtractionError.readerFailedToStart }

        var frames: [PoseFrame] = []
        var firstTimestamp: Double?
        let request = VNDetectHumanBodyPoseRequest()
        var lastAnalysed = -Double.infinity
        let minGap = 0.9 / max(1, maxAnalysedFps)
        let portrait = [.left, .right, .leftMirrored, .rightMirrored].contains(orientation)

        while let sampleBuffer = output.copyNextSampleBuffer() {
            if Task.isCancelled {
                reader.cancelReading()
                throw CancellationError()
            }
            guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }
            let stamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
            let first = firstTimestamp ?? stamp
            firstTimestamp = first
            // Thin out high frame rates.
            if stamp - lastAnalysed < minGap { continue }
            lastAnalysed = stamp

            let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: orientation, options: [:])
            try? handler.perform([request])

            let results = request.results ?? []
            let best = results.max { score($0) < score($1) }
            // Vision normalizes x by the width and y by the height of the upright picture; angles need the ratio.
            let width = Double(CVPixelBufferGetWidth(buffer)), height = Double(CVPixelBufferGetHeight(buffer))
            let aspect: Double? = width > 0 && height > 0 ? (portrait ? height / width : width / height) : nil
            let frame = PoseFrame(time: stamp - first, joints: best.map(joints(of:)) ?? [],
                                  peopleDetected: results.count, aspect: aspect)
            frames.append(frame)

            if let progress {
                let image = frames.count % 2 == 0 ? previewImage(of: buffer, orientation: orientation) : nil
                progress(ClipExtractionProgress(fraction: duration > 0 ? min(1, (stamp - first) / duration) : 0,
                                                frame: frame, image: image, framesDone: frames.count))
            }
        }

        if reader.status == .failed {
            throw ExtractionError.readerFailed
        }
        return frames
    }

    /// A small upright still of a video frame, for the preview.
    private static func previewImage(of buffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> CGImage? {
        let image = CIImage(cvPixelBuffer: buffer).oriented(orientation)
        guard image.extent.width > 0 else { return nil }
        let scale = previewWidth / image.extent.width
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return imageContext.createCGImage(scaled, from: scaled.extent)
    }

    /// Maps a video track's `preferredTransform` to the orientation Vision needs to see the frame
    /// upright. Covers the four rotations iPhone recordings actually use.
    static func cgOrientation(for transform: CGAffineTransform) -> CGImagePropertyOrientation {
        switch (transform.a, transform.b, transform.c, transform.d) {
        case (0, 1, -1, 0): return .right
        case (0, -1, 1, 0): return .left
        case (-1, 0, 0, -1): return .down
        default: return .up
        }
    }

    private static func score(_ observation: VNHumanBodyPoseObservation) -> Float {
        guard let points = try? observation.recognizedPoints(.all) else { return 0 }
        return points.values.reduce(0) { $0 + $1.confidence }
    }

    private static func joints(of observation: VNHumanBodyPoseObservation) -> [Contracts.Joint] {
        jointMap.compactMap { vision, ours in
            guard let point = try? observation.recognizedPoint(vision), point.confidence > minJointConfidence else {
                return nil
            }
            // Vision: origin bottom-left. Ours (Contracts.Joint, like the rest of the app): origin top-left.
            return Contracts.Joint(name: ours, x: Double(point.location.x), y: 1 - Double(point.location.y),
                        confidence: Double(point.confidence))
        }
    }
}

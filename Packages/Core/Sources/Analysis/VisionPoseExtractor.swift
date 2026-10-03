import AVFoundation
import Contracts
import Foundation
import Vision

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

    /// Runs pose detection on every frame of `url`. `time` in the returned frames is seconds from the
    /// first frame, regardless of where the source video's own timestamps start.
    public static func extract(from url: URL) async throws -> [PoseFrame] {
        let asset = AVURLAsset(url: url)
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

        while let sampleBuffer = output.copyNextSampleBuffer() {
            guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }
            let stamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
            let first = firstTimestamp ?? stamp
            firstTimestamp = first

            let request = VNDetectHumanBodyPoseRequest()
            let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: orientation, options: [:])
            try? handler.perform([request])

            let results = request.results ?? []
            let best = results.max { score($0) < score($1) }
            frames.append(PoseFrame(time: stamp - first, joints: best.map(joints(of:)) ?? [],
                                    peopleDetected: results.count))
        }

        if reader.status == .failed {
            throw ExtractionError.readerFailed
        }
        return frames
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

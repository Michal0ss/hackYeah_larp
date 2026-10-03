import AVFoundation
import XCTest
@testable import Analysis

/// These tests exercise the `AVAssetReader` pipeline itself (frame count, timestamps, graceful
/// no-detection handling) against a generated solid-color clip. They can't check real joint
/// coordinates — that needs an actual recorded squat, which goes in `Fixtures/` once available
/// (see `Fixtures/README.md`).
final class VisionPoseExtractorTests: XCTestCase {
    private func makeSolidColorVideo(frameCount: Int, fps: Int32, size: CGSize) async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        for frameIndex in 0..<frameCount {
            while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.01) }
            var pixelBufferOut: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pixelBufferOut)
            guard let pixelBuffer = pixelBufferOut else { continue }
            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            if let base = CVPixelBufferGetBaseAddress(pixelBuffer) {
                memset(base, 128, CVPixelBufferGetBytesPerRow(pixelBuffer) * Int(size.height))
            }
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
            adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: CMTimeValue(frameIndex), timescale: fps))
        }

        input.markAsFinished()
        let done = expectation(description: "writer finished")
        writer.finishWriting { done.fulfill() }
        await fulfillment(of: [done], timeout: 5)
        return url
    }

    func testExtractReturnsOneFramePerVideoFrameWithIncreasingTime() async throws {
        let url = try await makeSolidColorVideo(frameCount: 5, fps: 10, size: CGSize(width: 64, height: 64))
        defer { try? FileManager.default.removeItem(at: url) }

        let frames = try await VisionPoseExtractor.extract(from: url)

        XCTAssertEqual(frames.count, 5)
        XCTAssertEqual(frames.first?.time ?? -1, 0, accuracy: 0.001)
        for (earlier, later) in zip(frames, frames.dropFirst()) {
            XCTAssertLessThan(earlier.time, later.time)
        }
        // No person in a solid color frame: Vision should find nothing, not crash.
        XCTAssertTrue(frames.allSatisfy { $0.joints.isEmpty })
    }

    func testOrientationMappingForStandardIPhoneRotations() {
        // The four transforms AVFoundation actually produces for iPhone recordings.
        XCTAssertEqual(VisionPoseExtractor.cgOrientation(for: .identity), .up)
        XCTAssertEqual(VisionPoseExtractor.cgOrientation(for: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 0, ty: 0)), .right)
        XCTAssertEqual(VisionPoseExtractor.cgOrientation(for: CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: 0)), .left)
        XCTAssertEqual(VisionPoseExtractor.cgOrientation(for: CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: 0, ty: 0)), .down)
    }

    func testThrowsForAMissingFile() async {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("does-not-exist-\(UUID()).mov")
        do {
            _ = try await VisionPoseExtractor.extract(from: missing)
            XCTFail("expected an error for a missing file")
        } catch {
            // Any error is correct here; we only need extraction to fail cleanly instead of hanging/crashing.
        }
    }
}

import XCTest
@testable import Relay

final class OnboardingReviewLayoutTests: XCTestCase {

    func test_layout_fillsCanvasEdgeToEdge_forFourCandidates() {
        let ids = (0..<4).map { _ in UUID() }
        let canvasSize = CGSize(width: 1200, height: 800)

        let frames = OnboardingReviewLayout.layout(candidateIDs: ids, canvasSize: canvasSize)

        XCTAssertEqual(frames.count, 4)
        for id in ids {
            XCTAssertNotNil(frames[id])
        }
        let union = frames.values.reduce(CGRect.null) { $0.union($1) }
        XCTAssertEqual(union, CGRect(origin: .zero, size: canvasSize))
    }

    func test_layout_fillsFullCanvas_forSingleCandidate() {
        let id = UUID()
        let canvasSize = CGSize(width: 1200, height: 800)

        let frames = OnboardingReviewLayout.layout(candidateIDs: [id], canvasSize: canvasSize)

        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames[id], CGRect(origin: .zero, size: canvasSize))
    }

    func test_layout_isEmpty_forNoCandidates() {
        let frames = OnboardingReviewLayout.layout(candidateIDs: [], canvasSize: CGSize(width: 1200, height: 800))

        XCTAssertTrue(frames.isEmpty)
    }

    func test_offsetAndSize_usesRawOriginWithNoRecentering() {
        let rect = CGRect(x: 100, y: 50, width: 300, height: 200)

        let result = OnboardingReviewLayout.offsetAndSize(for: rect)

        XCTAssertEqual(result.offset, CGSize(width: 100, height: 50))
        XCTAssertEqual(result.size, CGSize(width: 300, height: 200))
    }
}

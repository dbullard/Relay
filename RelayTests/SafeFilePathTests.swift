import XCTest
@testable import Relay

final class SafeFilePathTests: XCTestCase {
    private var folder: URL!
    private var outside: URL!

    override func setUpWithError() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SafeFilePathTests-\(UUID().uuidString)", isDirectory: true)
        folder = root.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        outside = root.appendingPathComponent("secret.txt")
        try Data("secret".utf8).write(to: outside)
        try Data("jpg".utf8).write(to: folder.appendingPathComponent("Ann Lee.jpg"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder.deletingLastPathComponent())
    }

    func testResolvesPlainFilenameInsideFolder() {
        let path = SafeFilePath.resolve(filename: "Ann Lee.jpg", inFolder: folder.path)
        XCTAssertEqual(path.map { URL(fileURLWithPath: $0).lastPathComponent }, "Ann Lee.jpg")
    }

    func testRejectsParentTraversal() {
        XCTAssertNil(SafeFilePath.resolve(filename: "../secret.txt", inFolder: folder.path))
        XCTAssertNil(SafeFilePath.resolve(filename: "../../secret.txt", inFolder: folder.path))
    }

    func testRejectsEncodedAndNestedSeparators() {
        XCTAssertNil(SafeFilePath.resolve(filename: "sub/x.jpg", inFolder: folder.path))
        XCTAssertNil(SafeFilePath.resolve(filename: "..\\secret.txt", inFolder: folder.path))
    }

    func testRejectsAbsolutePath() {
        XCTAssertNil(SafeFilePath.resolve(filename: outside.path, inFolder: folder.path))
    }

    func testRejectsSymlinkEscapingFolder() throws {
        let link = folder.appendingPathComponent("evil.jpg")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        XCTAssertNil(SafeFilePath.resolve(filename: "evil.jpg", inFolder: folder.path))
    }

    func testRejectsEmptyAndDotNames() {
        XCTAssertNil(SafeFilePath.resolve(filename: "", inFolder: folder.path))
        XCTAssertNil(SafeFilePath.resolve(filename: ".", inFolder: folder.path))
        XCTAssertNil(SafeFilePath.resolve(filename: "..", inFolder: folder.path))
        XCTAssertNil(SafeFilePath.resolve(filename: "a\0b.jpg", inFolder: folder.path))
    }
}

import XCTest
@testable import PowerUserInspectors

final class LineDiffTests: XCTestCase {
    func testIdenticalContentsProducesOnlyUnchangedLines() {
        let changes = LineDiff.diff(old: ["a", "b", "c"], new: ["a", "b", "c"])
        XCTAssertEqual(changes, [
            LineDiff.Change(kind: .unchanged, text: "a"),
            LineDiff.Change(kind: .unchanged, text: "b"),
            LineDiff.Change(kind: .unchanged, text: "c")
        ])
    }

    func testEmptyOldIsAllInsertions() {
        let changes = LineDiff.diff(old: [], new: ["a", "b"])
        XCTAssertEqual(changes, [
            LineDiff.Change(kind: .insertion, text: "a"),
            LineDiff.Change(kind: .insertion, text: "b")
        ])
    }

    func testEmptyNewIsAllDeletions() {
        let changes = LineDiff.diff(old: ["a", "b"], new: [])
        XCTAssertEqual(changes, [
            LineDiff.Change(kind: .deletion, text: "a"),
            LineDiff.Change(kind: .deletion, text: "b")
        ])
    }

    func testBothEmptyProducesNoChanges() {
        XCTAssertEqual(LineDiff.diff(old: [], new: []), [])
    }

    func testMixedInsertDeleteAroundUnchangedAnchor() {
        // old: 1 2 3        new: 1 4 3
        let changes = LineDiff.diff(old: ["1", "2", "3"], new: ["1", "4", "3"])
        XCTAssertEqual(changes, [
            LineDiff.Change(kind: .unchanged, text: "1"),
            LineDiff.Change(kind: .deletion, text: "2"),
            LineDiff.Change(kind: .insertion, text: "4"),
            LineDiff.Change(kind: .unchanged, text: "3")
        ])
    }

    func testAppendedLineIsASingleInsertion() {
        let changes = LineDiff.diff(old: ["one", "two"], new: ["one", "two", "three"])
        XCTAssertEqual(changes, [
            LineDiff.Change(kind: .unchanged, text: "one"),
            LineDiff.Change(kind: .unchanged, text: "two"),
            LineDiff.Change(kind: .insertion, text: "three")
        ])
    }

    /// The diff, read in order, must always be able to reconstruct both
    /// inputs — this is the correctness property that actually matters for
    /// a diff view, more than matching any particular "canonical" edit
    /// script.
    func testDiffReconstructsBothInputsForVariousPairs() {
        let cases: [(old: [String], new: [String])] = [
            (["a", "b", "c", "d"], ["a", "x", "c", "y", "d"]),
            (["1", "2", "3"], ["3", "2", "1"]),
            (["line"], []),
            ([], ["line"]),
            (["same", "same"], ["same"]),
            (["config = true", "port = 8080", "debug = false"], ["config = true", "port = 9090", "debug = false", "verbose = true"])
        ]

        for testCase in cases {
            let changes = LineDiff.diff(old: testCase.old, new: testCase.new)
            let reconstructedOld = changes.filter { $0.kind != .insertion }.map(\.text)
            let reconstructedNew = changes.filter { $0.kind != .deletion }.map(\.text)
            XCTAssertEqual(reconstructedOld, testCase.old, "old mismatch for \(testCase)")
            XCTAssertEqual(reconstructedNew, testCase.new, "new mismatch for \(testCase)")
        }
    }

    func testConvenienceStringOverloadSplitsOnNewlines() {
        let changes = LineDiff.diff(oldContents: "a\nb", newContents: "a\nc")
        XCTAssertEqual(changes, [
            LineDiff.Change(kind: .unchanged, text: "a"),
            LineDiff.Change(kind: .deletion, text: "b"),
            LineDiff.Change(kind: .insertion, text: "c")
        ])
    }
}

import XCTest
@testable import KachelCore

/// The model's rules, after any sequence of operations: tried with random
/// sequences (the same ones every run), and a few cases on their own.
final class StackSetInvariantTests: XCTestCase {
    /// A tiny random generator with a fixed seed, so a failure repeats.
    struct Rand {
        var state: UInt64
        mutating func next(_ n: Int) -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int((state >> 33) % UInt64(n))
        }
    }

    func check(_ ss: StackSet, _ step: String, file: StaticString = #filePath, line: UInt = #line) {
        let all = ss.allWindows
        XCTAssertEqual(all.count, Set(all).count, "a window on two workspaces, or twice on one (\(step))", file: file, line: line)
        XCTAssertEqual(ss.screenWorkspace.count, Set(ss.screenWorkspace).count, "a workspace on two displays (\(step))", file: file, line: line)
        XCTAssertFalse(ss.screenWorkspace.isEmpty, step, file: file, line: line)
        XCTAssertTrue(ss.screenWorkspace.allSatisfy { ss.workspaces.indices.contains($0) }, "a display shows no workspace (\(step))", file: file, line: line)
        XCTAssertTrue(ss.screenWorkspace.indices.contains(ss.currentScreen), "current display out of range (\(step))", file: file, line: line)
        for ws in ss.workspaces {
            if let f = ws.focused { XCTAssertTrue(ws.windows.contains(f), "focus on a window elsewhere (\(step))", file: file, line: line) }
            XCTAssertTrue(ws.ratio >= 0.1 && ws.ratio <= 0.9, "ratio \(ws.ratio) (\(step))", file: file, line: line)
            XCTAssertTrue(ws.weights.keys.allSatisfy(ws.windows.contains), "a size for a window not here (\(step))", file: file, line: line)
        }
    }

    func testRandomSequencesKeepTheRules() {
        for seed in 1...200 {
            var r = Rand(state: UInt64(seed))
            var ss = StackSet(tags: (1...9).map(String.init), screenCount: 1 + r.next(3))
            var nextID: WindowID = 1
            for n in 0..<120 {
                let windows = ss.allWindows
                let some = { windows.isEmpty ? nil : windows[r.next(windows.count)] }
                let op = r.next(17)
                switch op {
                case 0, 1: ss.insert(nextID, into: r.next(2) == 0 ? nil : r.next(ss.workspaces.count)); nextID += 1
                case 2: if let w = some() { ss.remove(w) }
                case 3: ss.greedyView(r.next(ss.workspaces.count))
                case 4: ss.view(r.next(ss.workspaces.count))
                case 5: if let w = some() { ss.shift(w, to: r.next(ss.workspaces.count)) }
                case 6: if let a = some(), let b = some() { ss.swap(a, b) }
                case 7: ss.focusDown(); ss.swapUp()
                case 8: ss.swapMaster(); ss.focusUp()
                case 9: ss.setScreenCount(1 + r.next(3))
                case 10: ss.setTags((1...(1 + r.next(9))).map(String.init))
                case 11: if let w = some() { _ = ss.focus(w) }
                case 12: ss.scaleFocusedWeight(r.next(2) == 0 ? 1.5 : 0.6)
                case 13: if let w = some() { ss.toggleFloating(w) }
                case 14: ss.adjustRatio(r.next(2) == 0 ? 0.3 : -0.3)
                case 15: ss.focusScreen(r.next(3))
                default: if let w = some() { ss.replace(w, with: nextID); nextID += 1 }
                }
                check(ss, "seed \(seed), step \(n), operation \(op)")
            }
        }
    }

    /// Fewer workspaces in the config: a display whose workspace is gone
    /// gets another, and the other display keeps the one it showed.
    func testRemovingAWorkspaceKeepsTheOtherDisplays() {
        var ss = StackSet(tags: (1...9).map(String.init), screenCount: 2)
        ss.greedyView(8)                       // display 1 shows 9
        ss.focusScreen(1)
        ss.greedyView(1)                       // display 2 shows 2
        ss.setTags(["1", "2", "3"])
        XCTAssertEqual(ss.screenWorkspace[1], 1, "display 2 still shows 2")
        XCTAssertNotEqual(ss.screenWorkspace[0], 1)
        XCTAssertEqual(ss.currentScreen, 1, "focus stays on display 2")
    }

    func testDownToOneWorkspace() {
        var ss = StackSet(tags: (1...9).map(String.init), screenCount: 2)
        ss.insert(1, into: 4)
        ss.insert(2, into: 8)
        ss.toggleFloating(2)
        ss.setTags(["only"])
        XCTAssertEqual(ss.workspaces.count, 1)
        XCTAssertEqual(Set(ss.workspaces[0].windows), [1, 2], "no window lost")
        XCTAssertTrue(ss.floating.contains(2), "still floating")
        XCTAssertEqual(ss.screenWorkspace, [0])
        check(ss, "down to one")
    }

    /// Sizes belong to a window in its workspace: swapped across workspaces,
    /// both start over (as when moved); within one, they go along.
    func testSwapAndSizes() {
        var ss = StackSet(tags: ["1", "2"], screenCount: 1)
        ss.insert(1, into: 0); ss.insert(2, into: 0); ss.insert(3, into: 1)
        ss.setWeights([1: 1.5, 2: 0.8], workspace: 0)
        ss.setWeights([3: 2], workspace: 1)
        ss.swap(1, 2)
        XCTAssertEqual(ss.workspaces[0].weights, [1: 1.5, 2: 0.8], "within a workspace: sizes go along")
        ss.swap(1, 3)
        XCTAssertEqual(ss.workspaces[0].weights, [2: 0.8])
        XCTAssertEqual(ss.workspaces[1].weights, [:])
        check(ss, "swaps")
    }

    /// A saved state that's old, edited or damaged gives sensible values.
    func testRestoreKeepsValuesSensible() {
        var before = StackSet(tags: ["1", "2", "3"], screenCount: 1)
        before.insert(1)
        var snap = before.snapshot
        snap.ratios = [0: 7, 1: -2, 2: .nan]
        snap.nMaster = [0: -3, 1: 999]
        var ss = StackSet(tags: ["1", "2", "3"], screenCount: 1)
        ss.restore(snap, existing: [1])
        XCTAssertEqual(ss.workspaces.map(\.ratio), [0.9, 0.1, 0.5])
        XCTAssertEqual(ss.workspaces[0].nMaster, 0)
        XCTAssertEqual(ss.workspaces[1].nMaster, 50)
    }

    func testGapIsNeverNegative() throws {
        XCTAssertEqual(try Settings.parse("gap: -10").gap, 0)
    }
}

import AppKit
import SwiftUI
import XCTest

/// Pictures of Kachel's own UI, compared with reference images.
///
/// Fonts and controls look a little different on every macOS version, so the
/// references are kept per version (`__Snapshots__/macOS-26.7/…`). Without a
/// reference for this version, the test records one and is skipped.
///
/// Pictures are only compared on the developer's Mac: another Mac (CI's
/// virtual one) smooths text slightly differently, so pixels never match
/// across machines. In CI the checks that hold everywhere still run (the
/// picture isn't blank, plus each test's own checks). With
/// one, a change shows as a failure, and the actual image and a picture of
/// the differences are written next to it (`….actual.png`, `….diff.png`).
///
/// Re-record after an intended change:  KACHEL_RECORD_SNAPSHOTS=1 swift test
enum Snapshot {
    static let folder: URL = {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("__Snapshots__/macOS-\(v.majorVersion).\(v.minorVersion)")
    }()
    static let recording = ProcessInfo.processInfo.environment["KACHEL_RECORD_SNAPSHOTS"] == "1"

    /// A view drawn as it would be on screen (AppKit controls included), at 2×.
    @MainActor
    static func image(of view: NSView, appearance: NSAppearance? = NSAppearance(named: .darkAqua)) -> NSBitmapImageRep {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(origin: CGPoint(x: -20_000, y: -20_000), size: view.frame.size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        // Always 2× (a Retina screen), whatever screen this Mac has.
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width * 2), pixelsHigh: Int(view.bounds.height * 2),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = view.bounds.size
        // Colours like labelColor are resolved while drawing: with the window's appearance.
        view.effectiveAppearance.performAsCurrentDrawingAppearance { view.cacheDisplay(in: view.bounds, to: rep) }
        window.contentView = nil
        return rep
    }

    /// A SwiftUI view in a real hosting view, so pickers and toggles are drawn.
    @MainActor
    static func image<V: View>(of view: V, size: CGSize, dark: Bool = true) -> NSBitmapImageRep {
        let host = NSHostingView(rootView: view.environment(\.colorScheme, dark ? .dark : .light))
        host.frame = NSRect(origin: .zero, size: size)
        return image(of: host, appearance: NSAppearance(named: dark ? .darkAqua : .aqua))
    }

    /// Something drawn with AppKit calls into an image of `size` points.
    static func image(size: NSSize, dark: Bool = true, _ draw: () -> Void) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSAppearance(named: dark ? .darkAqua : .aqua)!.performAsCurrentDrawingAppearance(draw)
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    /// Compare with the reference called `name`.
    ///  - tolerance: share of pixels that may differ noticeably (anti-aliasing).
    static func check(_ rep: NSBitmapImageRep, _ name: String, tolerance: Double = 0.0001,
                      file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertGreaterThan(distinctColours(rep), 3, "\(name): the image is (nearly) blank", file: file, line: line)
        if ProcessInfo.processInfo.environment["CI"] != nil {
            throw XCTSkip("\(name): pictures are compared on the developer's Mac only")
        }
        let ref = folder.appendingPathComponent("\(name).png")
        guard !recording, let data = try? Data(contentsOf: ref), let expected = NSBitmapImageRep(data: data) else {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try png(rep).write(to: ref)
            throw XCTSkip("\(name): recorded a new reference for this macOS version at \(ref.path)")
        }
        guard expected.pixelsWide == rep.pixelsWide, expected.pixelsHigh == rep.pixelsHigh else {
            try png(rep).write(to: folder.appendingPathComponent("\(name).actual.png"))
            XCTFail("\(name): size changed from \(expected.pixelsWide)×\(expected.pixelsHigh) to \(rep.pixelsWide)×\(rep.pixelsHigh)",
                    file: file, line: line)
            return
        }
        let (share, diff) = difference(expected, rep)
        if ProcessInfo.processInfo.environment["KACHEL_SNAPSHOT_STATS"] != nil {
            print("SNAPSHOT \(name): \(share)")
        }
        let actualURL = folder.appendingPathComponent("\(name).actual.png")
        let diffURL = folder.appendingPathComponent("\(name).diff.png")
        if share > tolerance {
            try png(rep).write(to: actualURL)
            try png(diff).write(to: diffURL)
            XCTFail("\(name): \(String(format: "%.2f", share * 100)) % of the pixels changed; see \(actualURL.lastPathComponent) and \(diffURL.lastPathComponent)",
                    file: file, line: line)
        } else {
            try? FileManager.default.removeItem(at: actualURL)
            try? FileManager.default.removeItem(at: diffURL)
        }
    }

    /// Every pixel as RGBA bytes, whatever format the image came in.
    static func rgba(_ rep: NSBitmapImageRep) -> [UInt8] {
        let w = rep.pixelsWide, h = rep.pixelsHigh
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        guard let cg = rep.cgImage else { return buf }
        buf.withUnsafeMutableBytes { p in
            let ctx = CGContext(data: p.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return buf
    }

    /// Share of pixels that differ by more than a bit, and an image of them (red).
    static func difference(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep) -> (Double, NSBitmapImageRep) {
        let w = a.pixelsWide, h = a.pixelsHigh
        let pa = rgba(a), pb = rgba(b)
        var out = [UInt8](repeating: 0, count: w * h * 4)
        var changed = 0
        for i in stride(from: 0, to: pa.count, by: 4) {
            var d = 0
            for c in 0..<4 { d = max(d, abs(Int(pa[i + c]) - Int(pb[i + c]))) }
            if d > 32 {
                changed += 1
                out[i] = 255; out[i + 3] = 255
            } else {
                out[i] = pb[i] / 4; out[i + 1] = pb[i + 1] / 4; out[i + 2] = pb[i + 2] / 4; out[i + 3] = 255
            }
        }
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: w * 4, bitsPerPixel: 32)!
        out.withUnsafeBytes { src in rep.bitmapData!.update(from: src.baseAddress!.assumingMemoryBound(to: UInt8.self), count: out.count) }
        return (Double(changed) / Double(max(1, w * h)), rep)
    }

    /// How many different colours (coarsely): a blank image has one or two.
    static func distinctColours(_ rep: NSBitmapImageRep) -> Int {
        let p = rgba(rep)
        var seen = Set<Int>()
        let step = max(4, (p.count / 4 / 4000) * 4)
        for i in stride(from: 0, to: p.count, by: step) where seen.count < 10 {
            seen.insert(Int(p[i] >> 4) << 8 | Int(p[i + 1] >> 4) << 4 | Int(p[i + 2] >> 4))
        }
        return seen.count
    }

    static func png(_ rep: NSBitmapImageRep) -> Data { rep.representation(using: .png, properties: [:])! }
}

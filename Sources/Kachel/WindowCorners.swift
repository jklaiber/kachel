import AppKit

/// How round a window's corners are. macOS has no API for it, but it
/// follows two things we can find out:
///  - which macOS the app was built for: apps built before macOS 26 keep the
///    old 10 pt corners (many Electron apps), newer ones get the rounder ones;
///  - on macOS 26, windows with a toolbar are rounder than plain ones.
enum WindowCorners {
    static func radius(of w: AppWindow) -> CGFloat {
        let os = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        guard os >= 26 else { return 10 }
        if let sdk = sdkMajor(pid: w.pid), sdk < 26 { return 10 }
        return hasToolbar(w) ? 26 : 16
    }

    private static func hasToolbar(_ w: AppWindow) -> Bool {
        guard let w = w as? AXWindow, let children = axCopy(w.element, kAXChildrenAttribute) as? [AXUIElement] else { return false }
        return children.contains { axString($0, kAXRoleAttribute) == kAXToolbarRole }
    }

    // MARK: - SDK version from the app's executable (LC_BUILD_VERSION)

    private static var cache: [String: Int?] = [:]

    static func sdkMajor(pid: pid_t) -> Int? {
        guard let url = NSRunningApplication(processIdentifier: pid)?.executableURL else { return nil }
        if let hit = cache[url.path] { return hit }
        let v = readSDK(url)
        cache[url.path] = v
        if let v { Log.info("border: \(url.lastPathComponent) is built for macOS \(v)") }
        return v
    }

    private static func readSDK(_ url: URL) -> Int? {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }
        func read(_ offset: UInt64, _ count: Int) -> Data? {
            try? fh.seek(toOffset: offset)
            return try? fh.read(upToCount: count)
        }
        func u32(_ d: Data, _ at: Int, big: Bool = false) -> UInt32 {
            let v = d.subdata(in: at..<at + 4).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
            return big ? UInt32(bigEndian: v) : UInt32(littleEndian: v)
        }
        guard let head = read(0, 8), head.count == 8 else { return nil }
        var sliceOffset: UInt64 = 0
        let magic = u32(head, 0, big: true)
        if magic == 0xCAFE_BABE || magic == 0xCAFE_BABF {                 // universal binary
            let n = Int(u32(head, 4, big: true))
            let entry = magic == 0xCAFE_BABE ? 20 : 32
            guard n > 0, n < 16, let arch = read(8, n * entry) else { return nil }
            var chosen: UInt64?
            for i in 0..<n {
                let base = i * entry
                let cpu = u32(arch, base, big: true)
                let off = magic == 0xCAFE_BABE
                    ? UInt64(u32(arch, base + 8, big: true))
                    : (UInt64(u32(arch, base + 8, big: true)) << 32) | UInt64(u32(arch, base + 12, big: true))
                if cpu == 0x0100_000C { chosen = off; break }             // arm64
                if chosen == nil { chosen = off }
            }
            guard let c = chosen else { return nil }
            sliceOffset = c
        }
        guard let mh = read(sliceOffset, 32), mh.count == 32, u32(mh, 0) == 0xFEED_FACF else { return nil }
        let ncmds = Int(u32(mh, 16)), size = Int(u32(mh, 20))
        guard size < 1_000_000, let cmds = read(sliceOffset + 32, size), cmds.count == size else { return nil }
        var at = 0
        for _ in 0..<ncmds {
            guard at + 8 <= cmds.count else { break }
            let cmd = u32(cmds, at), len = Int(u32(cmds, at + 4))
            if cmd == 0x32, at + 20 <= cmds.count { return Int(u32(cmds, at + 16) >> 16) }      // LC_BUILD_VERSION
            if cmd == 0x24, at + 16 <= cmds.count { return Int(u32(cmds, at + 12) >> 16) }      // LC_VERSION_MIN_MACOSX
            guard len > 0 else { break }
            at += len
        }
        return nil
    }
}

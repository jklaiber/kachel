import Foundation

/// The `kachel` command: talks to the running Kachel over a Unix socket that
/// only your user can open (~/Library/Application Support/Kachel/kachel.sock).
///
///   kachel workspace 2            any command from the config's keys:
///   kachel query windows          JSON for scripts (workspaces, windows, screens)
enum Ctl {
    static let socketPath = Watchdog.dir.appendingPathComponent("kachel.sock").path

    static let usage = """
    Usage: kachel <command>

      kachel <command>              run a command, as in the config's keys:
                                    workspace 2, shift 3, focus-down, next-layout,
                                    toggle-float, scratchpad notes, reload, …
      kachel query workspaces       JSON: every workspace, its layout and windows
      kachel query windows          JSON: every managed window
      kachel query screens          JSON: every display and the workspace on it
      kachel query focused          JSON: the focused window and workspace
      kachel settings               open Kachel's settings
      kachel version                Kachel's version (this command's and the app's)
      kachel dump                   write Kachel's state to ~/Library/Logs/Kachel.log

    All commands: https://jklaiber.github.io/kachel/keys/#all-commands
    """

    // MARK: - client

    /// Runs the command line and exits: 0 done, 1 Kachel said no, 2 not running.
    static func client(_ args: [String]) -> Never {
        let text = args.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        if text.isEmpty || ["help", "-h", "--help"].contains(text) {
            print(usage)
            exit(text.isEmpty ? 1 : 0)
        }
        if text == "version" || text == "--version" {
            print("kachel \(ownVersion)")
        }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0, connect(fd, socketPath) else {
            FileHandle.standardError.write("kachel: Kachel isn't running (no \(socketPath))\n".data(using: .utf8)!)
            exit(2)
        }
        sendAll(fd, text + "\n")
        let reply = readAll(fd)
        close(fd)
        // First line: "ok" or "error"; then the output.
        let status = reply.prefix { $0 != "\n" }
        let out = reply.drop { $0 != "\n" }.dropFirst()
        if status == "ok" {
            if !out.isEmpty { print(out, terminator: out.hasSuffix("\n") ? "" : "\n") }
            exit(0)
        }
        FileHandle.standardError.write("kachel: \(out)\n".data(using: .utf8)!)
        exit(1)
    }

    /// Homebrew's `kachel` is a symlink, so Bundle.main doesn't know the app:
    /// read the version from the app the link points into.
    private static var ownVersion: String {
        let exe = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let plist = exe.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Info.plist")
        return (NSDictionary(contentsOf: plist)?["CFBundleShortVersionString"] as? String) ?? AppVersion.string
    }

    // MARK: - server (in Kachel)

    private static var listener: DispatchSourceRead?

    /// Answer `kachel` commands. The handler runs on the main thread.
    static func listen(_ handle: @escaping (String) -> (ok: Bool, output: String)) {
        try? FileManager.default.createDirectory(at: Watchdog.dir, withIntermediateDirectories: true)
        unlink(socketPath)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0, bind(fd, socketPath), Darwin.listen(fd, 8) == 0 else {
            Log.info("kachel command: could not open \(socketPath): \(String(cString: strerror(errno)))")
            return
        }
        chmod(socketPath, 0o600)          // only you
        let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .global(qos: .userInitiated))
        src.setEventHandler {
            let c = accept(fd, nil, nil)
            guard c >= 0 else { return }
            var timeout = timeval(tv_sec: 2, tv_usec: 0)
            setsockopt(c, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            var nosig: Int32 = 1
            setsockopt(c, SOL_SOCKET, SO_NOSIGPIPE, &nosig, socklen_t(MemoryLayout<Int32>.size))
            let text = readLine(c).trimmingCharacters(in: .whitespacesAndNewlines)
            let r = DispatchQueue.main.sync { handle(text) }
            sendAll(c, (r.ok ? "ok" : "error") + "\n" + r.output)
            close(c)
        }
        src.resume()
        listener = src
        Log.info("kachel command listening on \(socketPath)")
    }

    static func stopListening() {
        listener?.cancel()
        listener = nil
        unlink(socketPath)
    }

    // MARK: - socket plumbing

    private static func address(_ path: String) -> sockaddr_un {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { buf in
            let bytes = Array(path.utf8.prefix(buf.count - 1)) + [0]
            buf.copyBytes(from: bytes)
        }
        return addr
    }

    private static func connect(_ fd: Int32, _ path: String) -> Bool {
        var addr = address(path)
        return withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        } == 0
    }

    private static func bind(_ fd: Int32, _ path: String) -> Bool {
        var addr = address(path)
        return withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        } == 0
    }

    private static func sendAll(_ fd: Int32, _ text: String) {
        var data = Array(text.utf8)
        while !data.isEmpty {
            let n = data.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
            if n <= 0 { return }
            data.removeFirst(n)
        }
    }

    private static func readLine(_ fd: Int32) -> String {
        var out: [UInt8] = []
        var byte: UInt8 = 0
        while out.count < 64 * 1024, read(fd, &byte, 1) == 1 {
            if byte == UInt8(ascii: "\n") { break }
            out.append(byte)
        }
        return String(decoding: out, as: UTF8.self)
    }

    private static func readAll(_ fd: Int32) -> String {
        var out: [UInt8] = []
        var buf = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            let n = read(fd, &buf, buf.count)
            if n <= 0 { break }
            out.append(contentsOf: buf[0..<n])
        }
        return String(decoding: out, as: UTF8.self)
    }
}

import Foundation
import KachelCore

/// Three/four-finger swipes, read from the trackpad through Apple's private
/// MultitouchSupport framework (the same thing BetterTouchTool and friends
/// use). Loaded at runtime: if it's missing or changes, gestures are simply
/// off and nothing else is affected.
final class Gestures {
    enum Direction: String { case left, right, up, down }

    /// Called on the main thread when a swipe is recognised.
    var onSwipe: ((Direction) -> Void)?
    private(set) var running = false

    private var devices: [UnsafeMutableRawPointer] = []
    private var deviceList: CFArray?          // keeps the device objects alive
    fileprivate var fingers = 3

    // Tracking state (touched only on the multitouch thread).
    fileprivate var start: (x: Float, y: Float)?
    fileprivate var fired = false

    static let shared = Gestures()

    func start(fingers: Int) {
        self.fingers = fingers
        guard !running else { return }
        guard let mt = MT.load() else {
            Log.info("gestures: MultitouchSupport not available, swipes are off")
            return
        }
        let cfList = mt.createList()?.takeRetainedValue()
        guard let cfList, case let list = cfList as [AnyObject], !list.isEmpty else {
            Log.info("gestures: no trackpad found")
            return
        }
        for dev in list {
            let ptr = Unmanaged.passUnretained(dev).toOpaque()
            mt.register(ptr, contactCallback)
            mt.start(ptr, 0)
            devices.append(ptr)
        }
        deviceList = cfList
        running = true
        Log.info("gestures: listening on \(devices.count) trackpad(s), \(fingers) fingers")
    }

    func stop() {
        guard running, let mt = MT.load() else { return }
        for d in devices {
            mt.unregister(d, contactCallback)
            mt.stop(d)
        }
        devices.removeAll()
        deviceList = nil
        running = false
        Log.info("gestures: stopped")
    }

    /// Feed one frame of touches. Positions are normalised 0…1, y up.
    fileprivate func frame(_ points: [(x: Float, y: Float)]) {
        guard points.count == fingers else {
            // Lifting (or adding) fingers ends the gesture.
            if points.isEmpty || points.count < fingers { start = nil; fired = false }
            return
        }
        let cx = points.map(\.x).reduce(0, +) / Float(points.count)
        let cy = points.map(\.y).reduce(0, +) / Float(points.count)
        guard let s = start else { start = (cx, cy); return }
        guard !fired else { return }
        let dx = cx - s.x, dy = cy - s.y
        // A deliberate swipe: far enough, and clearly in one direction.
        let threshold: Float = 0.12
        var dir: Direction?
        if abs(dx) > threshold, abs(dx) > 2 * abs(dy) { dir = dx < 0 ? .left : .right }
        else if abs(dy) > threshold, abs(dy) > 2 * abs(dx) { dir = dy > 0 ? .up : .down }
        guard let dir else { return }
        fired = true                      // one action per swipe
        DispatchQueue.main.async { self.onSwipe?(dir) }
    }
}

// MARK: - MultitouchSupport bindings

/// One finger, as MultitouchSupport reports it (96 bytes on 64-bit).
private struct MTTouch {
    var frame: Int32
    var timestamp: Double
    var identifier: Int32
    var state: Int32            // 4 = touching
    var fingerID: Int32
    var handID: Int32
    var posX: Float, posY: Float, velX: Float, velY: Float      // normalised
    var size: Float
    var zero1: Int32
    var angle: Float
    var majorAxis: Float
    var minorAxis: Float
    var absPosX: Float, absPosY: Float, absVelX: Float, absVelY: Float
    var zero2: Int32
    var zero3: Int32
    var density: Float
}

private typealias ContactCallback = @convention(c) (
    UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32

private let contactCallback: ContactCallback = { _, touches, count, _, _ in
    guard let touches, count > 0 else {
        Gestures.shared.frame([])
        return 0
    }
    let stride = MemoryLayout<MTTouch>.stride
    var points: [(x: Float, y: Float)] = []
    for i in 0..<Int(count) {
        let t = touches.load(fromByteOffset: i * stride, as: MTTouch.self)
        if t.state == 4 { points.append((t.posX, t.posY)) }
    }
    Gestures.shared.frame(points)
    return 0
}

private struct MT {
    let createList: @convention(c) () -> Unmanaged<CFArray>?
    let register: @convention(c) (UnsafeMutableRawPointer, ContactCallback) -> Void
    let unregister: @convention(c) (UnsafeMutableRawPointer, ContactCallback) -> Void
    let start: @convention(c) (UnsafeMutableRawPointer, Int32) -> Void
    let stop: @convention(c) (UnsafeMutableRawPointer) -> Void

    private static var cached: MT??

    static func load() -> MT? {
        if let c = cached { return c }
        defer { if cached == nil { cached = .some(nil) } }
        guard MemoryLayout<MTTouch>.stride == 96 else {
            Log.info("gestures: unexpected touch layout (\(MemoryLayout<MTTouch>.stride) bytes)")
            return nil
        }
        guard let h = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_LAZY)
        else { return nil }
        func sym<T>(_ name: String, _: T.Type) -> T? {
            dlsym(h, name).map { unsafeBitCast($0, to: T.self) }
        }
        guard let list = sym("MTDeviceCreateList", (@convention(c) () -> Unmanaged<CFArray>?).self),
              let reg = sym("MTRegisterContactFrameCallback",
                            (@convention(c) (UnsafeMutableRawPointer, ContactCallback) -> Void).self),
              let unreg = sym("MTUnregisterContactFrameCallback",
                              (@convention(c) (UnsafeMutableRawPointer, ContactCallback) -> Void).self),
              let start = sym("MTDeviceStart", (@convention(c) (UnsafeMutableRawPointer, Int32) -> Void).self),
              let stop = sym("MTDeviceStop", (@convention(c) (UnsafeMutableRawPointer) -> Void).self)
        else { return nil }
        let mt = MT(createList: list, register: reg, unregister: unreg, start: start, stop: stop)
        cached = .some(mt)
        return mt
    }
}

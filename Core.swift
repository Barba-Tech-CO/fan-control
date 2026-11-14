import Foundation
import IOKit

// MARK: SMC

struct Vers { var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0; var release: UInt16 = 0 }
struct PLimit { var version: UInt16 = 0, length: UInt16 = 0; var cpu: UInt32 = 0, gpu: UInt32 = 0, mem: UInt32 = 0 }
struct KeyInfo { var dataSize: UInt32 = 0, dataType: UInt32 = 0; var attrs: UInt8 = 0, pad0: UInt8 = 0, pad1: UInt8 = 0, pad2: UInt8 = 0 }
typealias Bytes32 = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                     UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
struct KeyData {
  var key: UInt32 = 0
  var vers = Vers()
  var pLimit = PLimit()
  var keyInfo = KeyInfo()
  var result: UInt8 = 0, status: UInt8 = 0, data8: UInt8 = 0
  var data32: UInt32 = 0
  var bytes: Bytes32 = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
}

enum SMCError: Error { case open, call(Int), size }

final class SMC {
  private var conn: io_connect_t = 0

  init() throws {
    precondition(MemoryLayout<KeyData>.size == 80, "SMC struct layout mismatch")
    let svc = IOServiceGetMatchingService(0, IOServiceMatching("AppleSMC"))
    guard svc != 0, IOServiceOpen(svc, mach_task_self_, 0, &conn) == KERN_SUCCESS else { throw SMCError.open }
    IOObjectRelease(svc)
  }

  private static func code(_ s: String) -> UInt32 { s.utf8.reduce(0) { $0 << 8 | UInt32($1) } }

  private func call(_ input: KeyData) throws -> KeyData {
    var inp = input, out = KeyData()
    var size = MemoryLayout<KeyData>.size
    guard IOConnectCallStructMethod(conn, 2, &inp, size, &out, &size) == KERN_SUCCESS else { throw SMCError.call(-1) }
    guard out.result == 0 else { throw SMCError.call(Int(out.result)) }
    return out
  }

  private func info(_ key: String) throws -> KeyInfo {
    var d = KeyData(); d.key = SMC.code(key); d.data8 = 9
    return try call(d).keyInfo
  }

  func read(_ key: String) throws -> [UInt8] {
    let i = try info(key)
    var d = KeyData(); d.key = SMC.code(key); d.keyInfo.dataSize = i.dataSize; d.data8 = 5
    var out = try call(d)
    return withUnsafeBytes(of: &out.bytes) { Array($0.prefix(Int(i.dataSize))) }
  }

  func write(_ key: String, _ value: [UInt8]) throws {
    let i = try info(key)
    guard Int(i.dataSize) == value.count else { throw SMCError.size }
    var d = KeyData(); d.key = SMC.code(key); d.keyInfo.dataSize = i.dataSize; d.data8 = 6
    withUnsafeMutableBytes(of: &d.bytes) { $0.copyBytes(from: value) }
    _ = try call(d)
  }

  func float(_ key: String) -> Float? {
    guard let b = try? read(key), b.count == 4 else { return nil }
    return b.withUnsafeBytes { $0.loadUnaligned(as: Float.self) }
  }
  func byte(_ key: String) -> UInt8? { try? read(key).first }
}

// MARK: Temperature (private HID sensor API)

@_silgen_name("IOHIDEventSystemClientCreate") func hidCreate(_ a: CFAllocator?) -> UnsafeMutableRawPointer
@_silgen_name("IOHIDEventSystemClientSetMatching") func hidSetMatching(_ c: UnsafeMutableRawPointer, _ m: CFDictionary) -> Int32
@_silgen_name("IOHIDEventSystemClientCopyServices") func hidServices(_ c: UnsafeMutableRawPointer) -> Unmanaged<CFArray>?
@_silgen_name("IOHIDServiceClientCopyEvent") func hidEvent(_ s: UnsafeRawPointer, _ t: Int64, _ o: Int32, _ to: Int64) -> Unmanaged<CFTypeRef>?
@_silgen_name("IOHIDEventGetFloatValue") func hidFloat(_ e: UnsafeRawPointer, _ f: Int32) -> Double

final class TempSensor {
  private let client = hidCreate(nil)
  init() { _ = hidSetMatching(client, ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary) }

  /// Hottest SoC temperature in °C, nil if unavailable.
  func maxC() -> Double? {
    guard let services = hidServices(client)?.takeRetainedValue() else { return nil }
    var best: Double?
    for i in 0..<CFArrayGetCount(services) {
      guard let svc = CFArrayGetValueAtIndex(services, i),
            let ev = hidEvent(svc, 15, 0, 0)?.takeRetainedValue() else { continue }
      let t = hidFloat(Unmanaged.passUnretained(ev).toOpaque(), 15 << 16)
      if t > 0 && t < 150 && t > (best ?? 0) { best = t }
    }
    return best
  }
}

func floatBytes(_ f: Float) -> [UInt8] { withUnsafeBytes(of: f) { Array($0) } }

struct Fan {
  let smc: SMC
  let min: Float, max: Float
  init(_ smc: SMC) { self.smc = smc; min = smc.float("F0Mn") ?? 1000; max = smc.float("F0Mx") ?? 4900 }
  var actual: Float { smc.float("F0Ac") ?? 0 }

  func setManual(_ rpm: Float) throws {
    try smc.write("F0Md", [1])
    try smc.write("F0Tg", floatBytes(Swift.min(Swift.max(rpm, min), max)))
  }
  func setAuto() { try? smc.write("F0Md", [0]) }
}

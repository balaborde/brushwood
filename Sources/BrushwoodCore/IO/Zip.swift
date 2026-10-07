import Compression
import Foundation

public enum ZipError: Error, LocalizedError {
    case invalidArchive(String)
    case unsupportedCompression(Int)
    case corrupt(String)

    public var errorDescription: String? {
        switch self {
        case .invalidArchive(let s): return "Invalid archive: \(s)"
        case .unsupportedCompression(let m): return "Unsupported zip compression method \(m)"
        case .corrupt(let s): return "Corrupt data: \(s)"
        }
    }
}

public enum CRC32 {
    static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    public static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
            for b in buf { crc = table[Int((crc ^ UInt32(b)) & 0xFF)] ^ (crc >> 8) }
        }
        return crc ^ 0xFFFF_FFFF
    }
}

/// Raw DEFLATE / gzip decoding through Apple's Compression framework.
public enum Inflate {
    /// Decodes a raw DEFLATE stream (RFC 1951).
    public static func rawDeflate(_ input: Data, expectedSize: Int? = nil) throws -> Data {
        if input.isEmpty { return Data() }
        var output = Data()
        let bufferSize = max(65536, expectedSize ?? 0)
        let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { dst.deallocate() }
        var stream = compression_stream(dst_ptr: dst, dst_size: 0, src_ptr: UnsafePointer(dst), src_size: 0, state: nil)
        guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
            throw ZipError.corrupt("cannot init inflater")
        }
        defer { compression_stream_destroy(&stream) }
        try input.withUnsafeBytes { (src: UnsafeRawBufferPointer) in
            stream.src_ptr = src.bindMemory(to: UInt8.self).baseAddress!
            stream.src_size = src.count
            while true {
                stream.dst_ptr = dst
                stream.dst_size = bufferSize
                let status = compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                let produced = bufferSize - stream.dst_size
                if produced > 0 { output.append(dst, count: produced) }
                if status == COMPRESSION_STATUS_END { break }
                if status == COMPRESSION_STATUS_ERROR { throw ZipError.corrupt("inflate failed") }
                if produced == 0 && stream.src_size == 0 { break }
            }
        }
        return output
    }

    /// Decodes a gzip member (RFC 1952) by skipping its header.
    public static func gzip(_ input: Data, expectedSize: Int? = nil) throws -> Data {
        let b = [UInt8](input.prefix(10))
        guard b.count == 10, b[0] == 0x1F, b[1] == 0x8B, b[2] == 8 else { throw ZipError.corrupt("not gzip") }
        let flags = b[3]
        var pos = 10
        let bytes = [UInt8](input)
        if flags & 0x04 != 0 {
            guard pos + 2 <= bytes.count else { throw ZipError.corrupt("gzip extra") }
            let xlen = Int(bytes[pos]) | Int(bytes[pos + 1]) << 8
            pos += 2 + xlen
        }
        if flags & 0x08 != 0 { while pos < bytes.count && bytes[pos] != 0 { pos += 1 }; pos += 1 }
        if flags & 0x10 != 0 { while pos < bytes.count && bytes[pos] != 0 { pos += 1 }; pos += 1 }
        if flags & 0x02 != 0 { pos += 2 }
        guard pos <= bytes.count else { throw ZipError.corrupt("gzip header") }
        return try rawDeflate(input.subdata(in: (input.startIndex + pos)..<input.endIndex), expectedSize: expectedSize)
    }

    /// Compresses with raw DEFLATE.
    public static func deflate(_ input: Data) -> Data? {
        if input.isEmpty { return Data([0x03, 0x00]) }
        let cap = input.count + input.count / 10 + 1024
        let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: cap)
        defer { dst.deallocate() }
        let n = input.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Int in
            compression_encode_buffer(dst, cap, src.bindMemory(to: UInt8.self).baseAddress!, src.count, nil, COMPRESSION_ZLIB)
        }
        return n > 0 ? Data(bytes: dst, count: n) : nil
    }
}

/// Minimal ZIP reader (stored + deflate entries).
public final class ZipReader {
    public struct Entry {
        public let name: String
        let method: Int
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    let data: Data
    public private(set) var entries: [String: Entry] = [:]
    public private(set) var orderedNames: [String] = []

    public init(data: Data) throws {
        self.data = data
        try parse()
    }

    private func u16(_ o: Int) -> Int { Int(data[data.startIndex + o]) | Int(data[data.startIndex + o + 1]) << 8 }
    private func u32(_ o: Int) -> Int { u16(o) | u16(o + 2) << 16 }

    private func parse() throws {
        let n = data.count
        guard n >= 22 else { throw ZipError.invalidArchive("too small") }
        var eocd = -1
        var i = n - 22
        while i >= max(0, n - 65557) {
            if u32(i) == 0x0605_4B50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw ZipError.invalidArchive("no end of central directory") }
        let count = u16(eocd + 10)
        var p = u32(eocd + 16)
        for _ in 0..<count {
            guard p + 46 <= n, u32(p) == 0x0201_4B50 else { throw ZipError.invalidArchive("bad central directory") }
            let method = u16(p + 10)
            let csize = u32(p + 20), usize = u32(p + 24)
            let nameLen = u16(p + 28), extraLen = u16(p + 30), commentLen = u16(p + 32)
            let lho = u32(p + 42)
            let nameData = data.subdata(in: (data.startIndex + p + 46)..<(data.startIndex + p + 46 + nameLen))
            let name = String(decoding: nameData, as: UTF8.self)
            entries[name] = Entry(name: name, method: method, compressedSize: csize, uncompressedSize: usize,
                                  localHeaderOffset: lho)
            orderedNames.append(name)
            p += 46 + nameLen + extraLen + commentLen
        }
    }

    public func read(_ name: String) throws -> Data? {
        guard let e = entries[name] else { return nil }
        let p = e.localHeaderOffset
        guard u32(p) == 0x0403_4B50 else { throw ZipError.invalidArchive("bad local header") }
        let nameLen = u16(p + 26), extraLen = u16(p + 28)
        let start = data.startIndex + p + 30 + nameLen + extraLen
        let raw = data.subdata(in: start..<(start + e.compressedSize))
        switch e.method {
        case 0: return raw
        case 8: return try Inflate.rawDeflate(raw, expectedSize: e.uncompressedSize)
        default: throw ZipError.unsupportedCompression(e.method)
        }
    }
}

/// Minimal ZIP writer.
public final class ZipWriter {
    private var out = Data()
    private var central = Data()
    private var count = 0

    public init() {}

    private static func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)] }
    private static func le32(_ v: Int) -> [UInt8] { le16(v & 0xFFFF) + le16((v >> 16) & 0xFFFF) }

    /// Adds a file. `compress` uses deflate when it actually saves space.
    public func add(name: String, data: Data, compress: Bool) {
        let nameBytes = [UInt8](name.utf8)
        let crc = Int(CRC32.checksum(data))
        var method = 0
        var payload = data
        if compress, let d = Inflate.deflate(data), d.count < data.count {
            method = 8
            payload = d
        }
        let offset = out.count
        var h: [UInt8] = []
        h += ZipWriter.le32(0x0403_4B50)
        h += ZipWriter.le16(20) + ZipWriter.le16(0x0800) + ZipWriter.le16(method)
        h += ZipWriter.le16(0) + ZipWriter.le16(0x21)  // time/date
        h += ZipWriter.le32(crc) + ZipWriter.le32(payload.count) + ZipWriter.le32(data.count)
        h += ZipWriter.le16(nameBytes.count) + ZipWriter.le16(0)
        out.append(contentsOf: h)
        out.append(contentsOf: nameBytes)
        out.append(payload)

        var c: [UInt8] = []
        c += ZipWriter.le32(0x0201_4B50)
        c += ZipWriter.le16(20) + ZipWriter.le16(20) + ZipWriter.le16(0x0800) + ZipWriter.le16(method)
        c += ZipWriter.le16(0) + ZipWriter.le16(0x21)
        c += ZipWriter.le32(crc) + ZipWriter.le32(payload.count) + ZipWriter.le32(data.count)
        c += ZipWriter.le16(nameBytes.count) + ZipWriter.le16(0) + ZipWriter.le16(0)
        c += ZipWriter.le16(0) + ZipWriter.le16(0) + ZipWriter.le32(0) + ZipWriter.le32(offset)
        central.append(contentsOf: c)
        central.append(contentsOf: nameBytes)
        count += 1
    }

    public func finish() -> Data {
        var result = out
        let cdOffset = result.count
        result.append(central)
        var e: [UInt8] = []
        e += ZipWriter.le32(0x0605_4B50) + ZipWriter.le16(0) + ZipWriter.le16(0)
        e += ZipWriter.le16(count) + ZipWriter.le16(count)
        e += ZipWriter.le32(central.count) + ZipWriter.le32(cdOffset) + ZipWriter.le16(0)
        result.append(contentsOf: e)
        return result
    }
}

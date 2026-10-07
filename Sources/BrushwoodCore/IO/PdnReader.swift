import Foundation

/// Reads Paint.NET's native .pdn files ("PDN3" header + XML + .NET BinaryFormatter graph + deferred pixel chunks).
public enum PdnReader {
    public enum PdnError: Error, LocalizedError {
        case notPdn
        case malformed(String)

        public var errorDescription: String? {
            switch self {
            case .notPdn: return "This is not a Paint.NET (.pdn) file."
            case .malformed(let s): return "The Paint.NET file is damaged or uses an unsupported version (\(s))."
            }
        }
    }

    public static func load(url: URL) throws -> Document {
        try decode(try Data(contentsOf: url))
    }

    public static func decode(_ fileData: Data) throws -> Document {
        let bytes = [UInt8](fileData)
        guard bytes.count > 9, bytes[0] == 0x50, bytes[1] == 0x44, bytes[2] == 0x4E, bytes[3] == 0x33 else {
            throw PdnError.notPdn
        }
        let headerSize = Int(bytes[4]) | Int(bytes[5]) << 8 | Int(bytes[6]) << 16
        var pos = 7 + headerSize
        guard pos + 2 <= bytes.count else { throw PdnError.malformed("header") }
        var payload: [UInt8]
        if bytes[pos] == 0x1F && bytes[pos + 1] == 0x8B {
            let gz = Data(bytes[pos...])
            payload = [UInt8](try Inflate.gzip(gz))
            pos = 0
        } else if bytes[pos] == 0x00 && bytes[pos + 1] == 0x01 {
            payload = bytes
            pos += 2
        } else {
            throw PdnError.malformed("format indicator")
        }

        let parser = NRBFParser(bytes: payload, position: pos)
        let root = try parser.parse()
        guard case .object(let docObj)? = parser.resolve(root) else { throw PdnError.malformed("no document") }
        let width = parser.int(docObj.member("width")) ?? 0
        let height = parser.int(docObj.member("height")) ?? 0
        guard width > 0, height > 0 else { throw PdnError.malformed("size") }

        // Layer list: LayerList derives from ArrayList ("_items" / "_size").
        guard case .object(let layerList)? = parser.resolve(docObj.member("layers")) else {
            throw PdnError.malformed("layers")
        }
        let size = parser.int(layerList.member("_size")) ?? 0
        guard case .array(let items)? = parser.resolve(layerList.member("_items")) else { throw PdnError.malformed("items") }

        struct LayerInfo {
            var props: LayerProperties
            var width: Int
            var height: Int
            var stride: Int
            var length: Int
        }
        var infos: [LayerInfo] = []
        for item in items.prefix(size) {
            guard case .object(let layer)? = parser.resolve(item) else { continue }
            var props = LayerProperties(name: "Layer")
            if case .object(let lp)? = parser.resolve(layer.member("Layer+properties") ?? layer.member("properties")) {
                props.name = parser.string(lp.member("name")) ?? "Layer"
                props.isVisible = parser.bool(lp.member("visible")) ?? true
                props.opacity = UInt8(clampInt(parser.int(lp.member("opacity")) ?? 255, 0, 255))
            }
            if case .object(let bp)? = parser.resolve(layer.member("BitmapLayer+properties") ?? layer.exactMember("properties")),
               case .object(let blendOp)? = parser.resolve(bp.member("blendOp")) {
                props.blendMode = blendMode(fromTypeName: blendOp.className)
            }
            guard case .object(let surf)? = parser.resolve(layer.member("surface")) else { continue }
            let w = parser.int(surf.member("width")) ?? width
            let h = parser.int(surf.member("height")) ?? height
            let stride = parser.int(surf.member("stride")) ?? w * 4
            var length = stride * h
            if case .object(let mb)? = parser.resolve(surf.member("scan0")) {
                length = parser.int(mb.member("length64")) ?? parser.int(mb.member("length")) ?? length
            }
            infos.append(LayerInfo(props: props, width: w, height: h, stride: stride, length: length))
        }
        guard !infos.isEmpty else { throw PdnError.malformed("no layers") }

        // Deferred MemoryBlock data follows the object graph, one block per layer in order.
        var p = parser.position
        var layers: [BitmapLayer] = []
        for info in infos {
            guard p + 5 <= payload.count else { throw PdnError.malformed("pixel data") }
            let formatVersion = payload[p]
            let chunkSize = be32(payload, p + 1)
            p += 5
            guard chunkSize > 0 else { throw PdnError.malformed("chunk size") }
            let chunkCount = (info.length + chunkSize - 1) / chunkSize
            var pixels = [UInt8](repeating: 0, count: info.length)
            for _ in 0..<chunkCount {
                guard p + 8 <= payload.count else { throw PdnError.malformed("chunk header") }
                let chunkNumber = be32(payload, p)
                let dataSize = be32(payload, p + 4)
                p += 8
                guard chunkNumber < chunkCount, p + dataSize <= payload.count else { throw PdnError.malformed("chunk") }
                let offset = chunkNumber * chunkSize
                let actual = min(chunkSize, info.length - offset)
                let raw = Data(payload[p..<(p + dataSize)])
                p += dataSize
                let chunk: Data = formatVersion == 0 ? try Inflate.gzip(raw, expectedSize: actual) : raw
                chunk.withUnsafeBytes { buf in
                    let n = min(actual, buf.count)
                    pixels.withUnsafeMutableBytes { dst in
                        dst.baseAddress!.advanced(by: offset).copyMemory(from: buf.baseAddress!, byteCount: n)
                    }
                }
            }
            let surface = Surface(width: width, height: height)
            let rows = min(info.height, height), cols = min(info.width, width)
            pixels.withUnsafeBytes { buf in
                let base = buf.baseAddress!
                for y in 0..<rows {
                    let src = base.advanced(by: y * info.stride).assumingMemoryBound(to: ColorBgra.self)
                    surface.row(y).update(from: src, count: cols)
                }
            }
            layers.append(BitmapLayer(surface: surface, properties: info.props))
        }
        return Document(width: width, height: height, layers: layers)
    }

    static func be32(_ b: [UInt8], _ o: Int) -> Int {
        Int(b[o]) << 24 | Int(b[o + 1]) << 16 | Int(b[o + 2]) << 8 | Int(b[o + 3])
    }

    static func blendMode(fromTypeName name: String) -> BlendMode {
        let short = name.components(separatedBy: "+").last ?? name
        let table: [String: BlendMode] = [
            "NormalBlendOp": .normal, "MultiplyBlendOp": .multiply, "AdditiveBlendOp": .additive,
            "ColorBurnBlendOp": .colorBurn, "ColorDodgeBlendOp": .colorDodge, "ReflectBlendOp": .reflect,
            "GlowBlendOp": .glow, "OverlayBlendOp": .overlay, "DifferenceBlendOp": .difference,
            "NegationBlendOp": .negation, "LightenBlendOp": .lighten, "DarkenBlendOp": .darken,
            "ScreenBlendOp": .screen, "XorBlendOp": .xor, "HardLightBlendOp": .hardLight, "SoftLightBlendOp": .softLight,
        ]
        return table[short] ?? .normal
    }
}

/// Parser for the MS-NRBF (.NET BinaryFormatter) stream format.
final class NRBFParser {
    indirect enum Value {
        case primitive(Any)
        case string(String)
        case reference(Int32)
        case null
        case object(NRBFObject)
        case array([Value])
    }

    final class NRBFObject {
        let id: Int32
        let className: String
        var memberNames: [String] = []
        var values: [Value] = []

        init(id: Int32, className: String) {
            self.id = id
            self.className = className
        }

        /// Member lookup tolerant of base-class prefixes ("ArrayList+_items" matches "_items").
        func member(_ name: String) -> Value? {
            if let i = memberNames.firstIndex(of: name) { return values[i] }
            if let i = memberNames.firstIndex(where: { $0.hasSuffix("+" + name) }) { return values[i] }
            return nil
        }

        func exactMember(_ name: String) -> Value? {
            memberNames.firstIndex(of: name).map { values[$0] }
        }
    }

    struct ClassMetadata {
        let name: String
        let memberNames: [String]
        let binaryTypes: [UInt8]
        let additional: [Any?]
    }

    let bytes: [UInt8]
    var position: Int
    var objects: [Int32: Value] = [:]
    var metadata: [Int32: ClassMetadata] = [:]
    var rootId: Int32 = 0

    init(bytes: [UInt8], position: Int) {
        self.bytes = bytes
        self.position = position
    }

    func parse() throws -> Value {
        while true {
            guard position < bytes.count else { throw PdnReader.PdnError.malformed("unexpected end") }
            let type = bytes[position]
            if type == 0x0B {
                position += 1
                break
            }
            _ = try readRecord()
        }
        return .reference(rootId)
    }

    func resolve(_ v: Value?) -> Value? {
        guard let v else { return nil }
        if case .reference(let id) = v { return objects[id].flatMap { resolveOnce($0) } }
        return v
    }

    private func resolveOnce(_ v: Value) -> Value {
        if case .reference(let id) = v, let o = objects[id] { return o }
        return v
    }

    func int(_ v: Value?) -> Int? {
        guard case .primitive(let p)? = resolve(v) else { return nil }
        switch p {
        case let x as Int32: return Int(x)
        case let x as Int64: return Int(x)
        case let x as UInt8: return Int(x)
        case let x as Int16: return Int(x)
        case let x as UInt16: return Int(x)
        case let x as UInt32: return Int(x)
        case let x as UInt64: return Int(x)
        case let x as Int8: return Int(x)
        default: return nil
        }
    }

    func bool(_ v: Value?) -> Bool? {
        guard case .primitive(let p)? = resolve(v) else { return nil }
        return p as? Bool
    }

    func string(_ v: Value?) -> String? {
        if case .string(let s)? = resolve(v) { return s }
        return nil
    }

    // MARK: Low-level readers

    private func need(_ n: Int) throws {
        if position + n > bytes.count { throw PdnReader.PdnError.malformed("truncated") }
    }

    private func u8() throws -> UInt8 {
        try need(1)
        defer { position += 1 }
        return bytes[position]
    }

    private func i32() throws -> Int32 {
        try need(4)
        let v = UInt32(bytes[position]) | UInt32(bytes[position + 1]) << 8 | UInt32(bytes[position + 2]) << 16
            | UInt32(bytes[position + 3]) << 24
        position += 4
        return Int32(bitPattern: v)
    }

    private func u64() throws -> UInt64 {
        try need(8)
        var v: UInt64 = 0
        for i in 0..<8 { v |= UInt64(bytes[position + i]) << (8 * UInt64(i)) }
        position += 8
        return v
    }

    private func lengthPrefixedString() throws -> String {
        var length = 0, shift = 0
        while true {
            let b = try u8()
            length |= Int(b & 0x7F) << shift
            if b & 0x80 == 0 { break }
            shift += 7
            if shift > 35 { throw PdnReader.PdnError.malformed("string length") }
        }
        try need(length)
        let s = String(decoding: bytes[position..<(position + length)], as: UTF8.self)
        position += length
        return s
    }

    private func primitive(_ type: UInt8) throws -> Any {
        switch type {
        case 1: return try u8() != 0
        case 2: return try u8()
        case 3:
            // UTF-8 char.
            let first = try u8()
            var extra = 0
            if first >= 0xF0 { extra = 3 } else if first >= 0xE0 { extra = 2 } else if first >= 0xC0 { extra = 1 }
            try need(extra)
            position += extra
            return first
        case 5: return try lengthPrefixedString()
        case 6: return Double(bitPattern: try u64())
        case 7:
            try need(2)
            let v = Int16(bitPattern: UInt16(bytes[position]) | UInt16(bytes[position + 1]) << 8)
            position += 2
            return v
        case 8: return try i32()
        case 9: return Int64(bitPattern: try u64())
        case 10: return Int8(bitPattern: try u8())
        case 11: return Float(bitPattern: UInt32(bitPattern: try i32()))
        case 12, 13: return Int64(bitPattern: try u64())
        case 14:
            try need(2)
            let v = UInt16(bytes[position]) | UInt16(bytes[position + 1]) << 8
            position += 2
            return v
        case 15: return UInt32(bitPattern: try i32())
        case 16: return try u64()
        case 17: return NSNull()
        case 18: return try lengthPrefixedString()
        default: throw PdnReader.PdnError.malformed("primitive type \(type)")
        }
    }

    // MARK: Records

    private func classInfo() throws -> (Int32, String, [String]) {
        let id = try i32()
        let name = try lengthPrefixedString()
        let count = Int(try i32())
        guard count >= 0 && count < 100_000 else { throw PdnReader.PdnError.malformed("member count") }
        var names: [String] = []
        for _ in 0..<count { names.append(try lengthPrefixedString()) }
        return (id, name, names)
    }

    private func memberTypeInfo(count: Int) throws -> ([UInt8], [Any?]) {
        var types: [UInt8] = []
        for _ in 0..<count { types.append(try u8()) }
        var additional: [Any?] = []
        for t in types {
            switch t {
            case 0, 7: additional.append(try u8())
            case 3: additional.append(try lengthPrefixedString())
            case 4:
                let n = try lengthPrefixedString()
                _ = try i32()
                additional.append(n)
            default: additional.append(nil)
            }
        }
        return (types, additional)
    }

    private func readMembers(_ obj: NRBFObject, _ meta: ClassMetadata) throws {
        obj.memberNames = meta.memberNames
        for (i, t) in meta.binaryTypes.enumerated() {
            if t == 0, let pt = meta.additional[i] as? UInt8 {
                obj.values.append(.primitive(try primitive(pt)))
            } else {
                obj.values.append(try readValueRecord())
            }
        }
    }

    /// Reads a record appearing as a member/element value.
    private func readValueRecord() throws -> Value {
        let v = try readRecord()
        return v
    }

    private var pendingNulls = 0

    @discardableResult
    private func readRecord() throws -> Value {
        let type = try u8()
        switch type {
        case 0x00:
            rootId = try i32()
            _ = try i32()
            _ = try i32()
            _ = try i32()
            return .null
        case 0x01:
            let id = try i32()
            let metaId = try i32()
            guard let meta = metadata[metaId] else { throw PdnReader.PdnError.malformed("metadata \(metaId)") }
            let obj = NRBFObject(id: id, className: meta.name)
            objects[id] = .object(obj)
            metadata[id] = meta
            try readMembers(obj, meta)
            return .object(obj)
        case 0x02, 0x03:
            let (id, name, names) = try classInfo()
            if type == 0x03 { _ = try i32() }
            // Without type info every member is a record.
            let meta = ClassMetadata(name: name, memberNames: names, binaryTypes: Array(repeating: 2, count: names.count),
                                     additional: Array(repeating: nil, count: names.count))
            metadata[id] = meta
            let obj = NRBFObject(id: id, className: name)
            objects[id] = .object(obj)
            try readMembers(obj, meta)
            return .object(obj)
        case 0x04, 0x05:
            let (id, name, names) = try classInfo()
            let (types, additional) = try memberTypeInfo(count: names.count)
            if type == 0x05 { _ = try i32() }
            let meta = ClassMetadata(name: name, memberNames: names, binaryTypes: types, additional: additional)
            metadata[id] = meta
            let obj = NRBFObject(id: id, className: name)
            objects[id] = .object(obj)
            try readMembers(obj, meta)
            return .object(obj)
        case 0x06:
            let id = try i32()
            let s = try lengthPrefixedString()
            objects[id] = .string(s)
            return .string(s)
        case 0x07:
            let id = try i32()
            let arrayType = try u8()
            let rank = Int(try i32())
            var total = 1
            for _ in 0..<rank { total *= Int(try i32()) }
            if [3, 4, 5].contains(arrayType) { for _ in 0..<rank { _ = try i32() } }
            let elemType = try u8()
            var addl: Any?
            switch elemType {
            case 0, 7: addl = try u8()
            case 3: addl = try lengthPrefixedString()
            case 4:
                addl = try lengthPrefixedString()
                _ = try i32()
            default: break
            }
            var elems: [Value] = []
            if elemType == 0, let pt = addl as? UInt8 {
                for _ in 0..<total { elems.append(.primitive(try primitive(pt))) }
            } else {
                try readElements(count: total, into: &elems)
            }
            objects[id] = .array(elems)
            return .array(elems)
        case 0x08:
            let pt = try u8()
            return .primitive(try primitive(pt))
        case 0x09:
            return .reference(try i32())
        case 0x0A:
            return .null
        case 0x0C:
            _ = try i32()
            _ = try lengthPrefixedString()
            // A library record precedes the actual value; read the next record as the value.
            return try readRecord()
        case 0x0D:
            pendingNulls = Int(try u8())
            return .null
        case 0x0E:
            pendingNulls = Int(try i32())
            return .null
        case 0x0F:
            let id = try i32()
            let length = Int(try i32())
            let pt = try u8()
            var elems: [Value] = []
            if pt == 2 {
                // Byte arrays can be large: store raw.
                try need(length)
                elems = [.primitive(Data(bytes[position..<(position + length)]))]
                position += length
            } else {
                elems.reserveCapacity(length)
                for _ in 0..<length { elems.append(.primitive(try primitive(pt))) }
            }
            objects[id] = .array(elems)
            return .array(elems)
        case 0x10, 0x11:
            let id = try i32()
            let length = Int(try i32())
            var elems: [Value] = []
            try readElements(count: length, into: &elems)
            objects[id] = .array(elems)
            return .array(elems)
        default:
            throw PdnReader.PdnError.malformed(String(format: "record 0x%02X", type))
        }
    }

    private func readElements(count: Int, into elems: inout [Value]) throws {
        while elems.count < count {
            pendingNulls = 0
            let v = try readRecord()
            if pendingNulls > 0 {
                for _ in 0..<pendingNulls { elems.append(.null) }
                pendingNulls = 0
            } else {
                elems.append(v)
            }
        }
    }
}

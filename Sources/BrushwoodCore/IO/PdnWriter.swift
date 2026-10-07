import Foundation

/// Writes Paint.NET (.pdn) files. The object graph mirrors, record for record, what Paint.NET 4.x's
/// BinaryFormatter produces (Document → LayerList → BitmapLayer → Surface/MemoryBlock...), followed by
/// the deferred pixel data in gzip-compressed 256 KB chunks.
public enum PdnWriter {
    /// Version written into the file; Paint.NET 4.x and later read files from this version.
    static let version = (major: 4, minor: 21, build: 6589, revision: 7045)

    static var versionString: String { "\(version.major).\(version.minor).\(version.build).\(version.revision)" }

    /// Paint.NET's `LayerBlendMode` / `UserBlendOps` names, indexed like Brushwood's first 14 blend modes.
    static let blendOpNames = ["Normal", "Multiply", "Additive", "ColorBurn", "ColorDodge", "Reflect", "Glow", "Overlay",
                               "Difference", "Negation", "Lighten", "Darken", "Screen", "Xor"]

    /// Blend modes Paint.NET 4 files can't express; they are written as Normal.
    public static func unsupportedBlendModes(in doc: Document) -> [BlendMode] {
        doc.layers.map(\.blendMode).filter { $0.rawValue >= blendOpNames.count }
    }

    public static func save(_ doc: Document, to url: URL) throws {
        let data = try encode(doc)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw ImageCodecError.writeFailed(error.localizedDescription)
        }
    }

    public static func encode(_ doc: Document) throws -> Data {
        var out = Data("PDN3".utf8)
        // XML header with a thumbnail, as Paint.NET writes it.
        var thumbAttr = ""
        if let thumb = Resampler.thumbnail(of: doc.flattened(), maxSize: 256), let png = ImageCodec.pngData(thumb) {
            thumbAttr = "<custom><thumb png=\"\(png.base64EncodedString())\" /></custom>"
        }
        let xml = "<pdnImage width=\"\(doc.width)\" height=\"\(doc.height)\" layers=\"\(doc.layers.count)\" "
            + "savedWithVersion=\"\(versionString)\">\(thumbAttr)</pdnImage>"
        let header = Data(xml.utf8)
        out.append(contentsOf: [UInt8(header.count & 0xFF), UInt8((header.count >> 8) & 0xFF), UInt8((header.count >> 16) & 0xFF)])
        out.append(header)
        out.append(contentsOf: [0x00, 0x01])
        out.append(graph(doc))
        for layer in doc.layers {
            out.append(try pixelChunks(layer.surface))
        }
        return out
    }

    // MARK: - Object graph

    private static func graph(_ doc: Document) -> Data {
        let w = NRBFWriter()
        let dataLib = "PaintDotNet.Data, Version=\(versionString), Culture=neutral, PublicKeyToken=null"
        let coreLib = "PaintDotNet.Core, Version=\(versionString), Culture=neutral, PublicKeyToken=null"
        let mscorlibString = "[System.String, mscorlib, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089]"
        let kvp = "System.Collections.Generic.KeyValuePair`2[\(mscorlibString),\(mscorlibString)]"
        let kvpArray = kvp + "[]"
        let n = doc.layers.count

        // Object ids, allocated in BinaryFormatter's breadth-first order.
        var next: Int32 = 1
        func id() -> Int32 {
            defer { next += 1 }
            return next
        }
        let docId = id()          // 1
        let dataLibId = id()      // 2
        let listId = id()         // 3
        let versionId = id()      // 4
        let docMetaId = id()      // 5
        let itemsId = id()        // 6
        let coreLibId = id()
        let layerIds = (0..<n).map { _ in id() }
        var propsIds: [Int32] = [], surfaceIds: [Int32] = [], layerPropsIds: [Int32] = []
        for _ in 0..<n {
            propsIds.append(id())
            surfaceIds.append(id())
            layerPropsIds.append(id())
        }
        var blendOpIds: [Int32] = [], memoryIds: [Int32] = []
        var layerMetaId: Int32 = 0
        for i in 0..<n {
            blendOpIds.append(id())
            memoryIds.append(id())
            if i == 0 { layerMetaId = id() }
        }

        w.header(rootId: docId)
        w.library(id: dataLibId, name: dataLib)
        // PaintDotNet.Document
        w.classWithMembersAndTypes(id: docId, name: "PaintDotNet.Document", members: [
            ("isDisposed", .primitive(.boolean)), ("layers", .class("PaintDotNet.LayerList", dataLibId)),
            ("width", .primitive(.int32)), ("height", .primitive(.int32)), ("savedWith", .systemClass("System.Version")),
            ("userMetadataItems", .systemClass(kvpArray)),
        ], libraryId: dataLibId)
        w.bool(false)
        w.reference(listId)
        w.int32(Int32(doc.width))
        w.int32(Int32(doc.height))
        w.reference(versionId)
        w.reference(docMetaId)
        // PaintDotNet.LayerList (an ArrayList).
        w.classWithMembersAndTypes(id: listId, name: "PaintDotNet.LayerList", members: [
            ("parent", .class("PaintDotNet.Document", dataLibId)), ("ArrayList+_items", .objectArray),
            ("ArrayList+_size", .primitive(.int32)), ("ArrayList+_version", .primitive(.int32)),
        ], libraryId: dataLibId)
        w.reference(docId)
        w.reference(itemsId)
        w.int32(Int32(n))
        w.int32(Int32(n))
        // System.Version
        w.systemClassWithMembersAndTypes(id: versionId, name: "System.Version", members: [
            ("_Major", .primitive(.int32)), ("_Minor", .primitive(.int32)), ("_Build", .primitive(.int32)),
            ("_Revision", .primitive(.int32)),
        ])
        w.int32(Int32(version.major))
        w.int32(Int32(version.minor))
        w.int32(Int32(version.build))
        w.int32(Int32(version.revision))
        // Empty document metadata.
        w.emptyBinaryArray(id: docMetaId, systemClass: kvp)
        // ArrayList items.
        w.arraySingleObject(id: itemsId, length: n)
        for lid in layerIds { w.reference(lid) }
        // Layers.
        w.library(id: coreLibId, name: coreLib)
        for (i, layer) in doc.layers.enumerated() {
            if i == 0 {
                w.classWithMembersAndTypes(id: layerIds[0], name: "PaintDotNet.BitmapLayer", members: [
                    ("properties", .class("PaintDotNet.BitmapLayer+BitmapLayerProperties", dataLibId)),
                    ("surface", .class("PaintDotNet.Surface", coreLibId)),
                    ("Layer+isDisposed", .primitive(.boolean)), ("Layer+width", .primitive(.int32)),
                    ("Layer+height", .primitive(.int32)),
                    ("Layer+properties", .class("PaintDotNet.Layer+LayerProperties", dataLibId)),
                ], libraryId: dataLibId)
            } else {
                w.classWithId(id: layerIds[i], metadataId: layerIds[0])
            }
            w.reference(propsIds[i])
            w.reference(surfaceIds[i])
            w.bool(false)
            w.int32(Int32(layer.surface.width))
            w.int32(Int32(layer.surface.height))
            w.reference(layerPropsIds[i])
        }
        // First-level objects of every layer, in queue order.
        var propsMetaByOp: [String: Int32] = [:]
        var blendEnumMeta: Int32 = 0
        var negative: Int32 = -1000
        for (i, layer) in doc.layers.enumerated() {
            let opName = "PaintDotNet.UserBlendOps+" + blendOpName(layer.blendMode) + "BlendOp"
            if let meta = propsMetaByOp[opName] {
                w.classWithId(id: propsIds[i], metadataId: meta)
            } else {
                w.classWithMembersAndTypes(id: propsIds[i], name: "PaintDotNet.BitmapLayer+BitmapLayerProperties", members: [
                    ("blendOp", .class(opName, dataLibId)),
                ], libraryId: dataLibId)
                propsMetaByOp[opName] = propsIds[i]
            }
            w.reference(blendOpIds[i])
            if i == 0 {
                w.classWithMembersAndTypes(id: surfaceIds[0], name: "PaintDotNet.Surface", members: [
                    ("width", .primitive(.int32)), ("height", .primitive(.int32)), ("stride", .primitive(.int32)),
                    ("scan0", .class("PaintDotNet.MemoryBlock", coreLibId)),
                ], libraryId: coreLibId)
            } else {
                w.classWithId(id: surfaceIds[i], metadataId: surfaceIds[0])
            }
            w.int32(Int32(layer.surface.width))
            w.int32(Int32(layer.surface.height))
            w.int32(Int32(layer.surface.width * 4))
            w.reference(memoryIds[i])
            if i == 0 {
                w.classWithMembersAndTypes(id: layerPropsIds[0], name: "PaintDotNet.Layer+LayerProperties", members: [
                    ("name", .string), ("userMetadataItems", .systemClass(kvpArray)), ("visible", .primitive(.boolean)),
                    ("isBackground", .primitive(.boolean)), ("opacity", .primitive(.byte)),
                    ("blendMode", .class("PaintDotNet.LayerBlendMode", dataLibId)),
                ], libraryId: dataLibId)
            } else {
                w.classWithId(id: layerPropsIds[i], metadataId: layerPropsIds[0])
            }
            w.objectString(id: id(), layer.name)
            w.reference(layerMetaId)
            w.bool(layer.isVisible)
            w.bool(i == 0)
            w.byte(layer.opacity)
            // Inline boxed enum.
            negative -= 1
            if i == 0 {
                blendEnumMeta = negative
                w.classWithMembersAndTypes(id: negative, name: "PaintDotNet.LayerBlendMode", members: [
                    ("value__", .primitive(.int32)),
                ], libraryId: dataLibId)
            } else {
                w.classWithId(id: negative, metadataId: blendEnumMeta)
            }
            w.int32(Int32(blendIndex(layer.blendMode)))
        }
        // Second-level objects.
        var opMeta: [String: Int32] = [:]
        for (i, layer) in doc.layers.enumerated() {
            let opName = "PaintDotNet.UserBlendOps+" + blendOpName(layer.blendMode) + "BlendOp"
            if let meta = opMeta[opName] {
                w.classWithId(id: blendOpIds[i], metadataId: meta)
            } else {
                w.classWithMembersAndTypes(id: blendOpIds[i], name: opName, members: [], libraryId: dataLibId)
                opMeta[opName] = blendOpIds[i]
            }
            if i == 0 {
                w.classWithMembersAndTypes(id: memoryIds[0], name: "PaintDotNet.MemoryBlock", members: [
                    ("length64", .primitive(.int64)), ("hasParent", .primitive(.boolean)), ("deferred", .primitive(.boolean)),
                ], libraryId: coreLibId)
            } else {
                w.classWithId(id: memoryIds[i], metadataId: memoryIds[0])
            }
            w.int64(Int64(layer.surface.byteCount))
            w.bool(false)
            w.bool(true)
            if i == 0 { w.emptyBinaryArray(id: layerMetaId, systemClass: kvp) }
        }
        w.messageEnd()
        return w.data
    }

    static func blendIndex(_ m: BlendMode) -> Int { m.rawValue < blendOpNames.count ? m.rawValue : 0 }
    static func blendOpName(_ m: BlendMode) -> String { blendOpNames[blendIndex(m)] }

    // MARK: - Deferred pixel data

    private static func pixelChunks(_ s: Surface) throws -> Data {
        let chunkSize = 0x40000
        let length = s.byteCount
        var out = Data([0x00])  // 0 = gzip-compressed chunks
        out.append(be32(chunkSize))
        let raw = UnsafeRawBufferPointer(start: UnsafeRawPointer(s.pixels), count: length)
        let count = (length + chunkSize - 1) / chunkSize
        // Compress chunks in parallel, then write them in order.
        var chunks = [Data?](repeating: nil, count: count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: count) { i in
            let start = i * chunkSize
            let piece = Data(raw[start..<min(length, start + chunkSize)])
            let gz = gzip(piece)
            lock.lock()
            chunks[i] = gz
            lock.unlock()
        }
        for (i, c) in chunks.enumerated() {
            guard let c else { throw ImageCodecError.writeFailed("compression failed") }
            out.append(be32(i))
            out.append(be32(c.count))
            out.append(c)
        }
        return out
    }

    private static func be32(_ v: Int) -> Data {
        Data([UInt8((v >> 24) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)])
    }

    /// Minimal gzip member around raw DEFLATE data.
    static func gzip(_ data: Data) -> Data {
        var out = Data([0x1F, 0x8B, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF])
        out.append(Inflate.deflate(data) ?? Data())
        let crc = CRC32.checksum(data)
        let size = UInt32(truncatingIfNeeded: data.count)
        for v in [crc, size] {
            out.append(contentsOf: [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)])
        }
        return out
    }
}

/// Emits MS-NRBF records.
final class NRBFWriter {
    enum PrimitiveType: UInt8 {
        case boolean = 1, byte = 2, int32 = 8, int64 = 9
    }

    enum MemberType {
        case primitive(PrimitiveType)
        case string
        case objectArray
        case systemClass(String)
        case `class`(String, Int32)

        var binaryType: UInt8 {
            switch self {
            case .primitive: return 0
            case .string: return 1
            case .systemClass: return 3
            case .class: return 4
            case .objectArray: return 5
            }
        }
    }

    private(set) var data = Data()

    func byte(_ v: UInt8) { data.append(v) }
    func bool(_ v: Bool) { data.append(v ? 1 : 0) }

    func int32(_ v: Int32) {
        let u = UInt32(bitPattern: v)
        data.append(contentsOf: [UInt8(u & 0xFF), UInt8((u >> 8) & 0xFF), UInt8((u >> 16) & 0xFF), UInt8((u >> 24) & 0xFF)])
    }

    func int64(_ v: Int64) {
        let u = UInt64(bitPattern: v)
        for i in 0..<8 { data.append(UInt8((u >> (8 * UInt64(i))) & 0xFF)) }
    }

    func string(_ s: String) {
        let bytes = Array(s.utf8)
        var n = bytes.count
        repeat {
            var b = UInt8(n & 0x7F)
            n >>= 7
            if n > 0 { b |= 0x80 }
            data.append(b)
        } while n > 0
        data.append(contentsOf: bytes)
    }

    func header(rootId: Int32) {
        byte(0x00)
        int32(rootId)
        int32(-1)
        int32(1)
        int32(0)
    }

    func library(id: Int32, name: String) {
        byte(0x0C)
        int32(id)
        string(name)
    }

    private func classInfo(id: Int32, name: String, members: [(String, MemberType)]) {
        int32(id)
        string(name)
        int32(Int32(members.count))
        for (n, _) in members { string(n) }
    }

    private func memberTypeInfo(_ members: [(String, MemberType)]) {
        for (_, t) in members { byte(t.binaryType) }
        for (_, t) in members {
            switch t {
            case .primitive(let p): byte(p.rawValue)
            case .systemClass(let name): string(name)
            case .class(let name, let lib):
                string(name)
                int32(lib)
            default: break
            }
        }
    }

    func classWithMembersAndTypes(id: Int32, name: String, members: [(String, MemberType)], libraryId: Int32) {
        byte(0x05)
        classInfo(id: id, name: name, members: members)
        memberTypeInfo(members)
        int32(libraryId)
    }

    func systemClassWithMembersAndTypes(id: Int32, name: String, members: [(String, MemberType)]) {
        byte(0x04)
        classInfo(id: id, name: name, members: members)
        memberTypeInfo(members)
    }

    func classWithId(id: Int32, metadataId: Int32) {
        byte(0x01)
        int32(id)
        int32(metadataId)
    }

    func objectString(id: Int32, _ s: String) {
        byte(0x06)
        int32(id)
        string(s)
    }

    func reference(_ id: Int32) {
        byte(0x09)
        int32(id)
    }

    func emptyBinaryArray(id: Int32, systemClass: String) {
        byte(0x07)
        int32(id)
        byte(0)          // single-dimensional
        int32(1)         // rank
        int32(0)         // length
        byte(3)          // element type: system class
        string(systemClass)
    }

    func arraySingleObject(id: Int32, length: Int) {
        byte(0x10)
        int32(id)
        int32(Int32(length))
    }

    func messageEnd() { byte(0x0B) }
}

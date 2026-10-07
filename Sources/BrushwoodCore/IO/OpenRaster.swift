import Foundation

/// OpenRaster (.ora): zipped PNG layers plus stack.xml. Brushwood's layered file format,
/// interoperable with Krita, GIMP and MyPaint.
public enum OpenRaster {
    public static func save(_ doc: Document, to url: URL) throws {
        let data = try encode(doc)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw ImageCodecError.writeFailed(error.localizedDescription)
        }
    }

    public static func encode(_ doc: Document) throws -> Data {
        let zip = ZipWriter()
        zip.add(name: "mimetype", data: Data("image/openraster".utf8), compress: false)
        var xml = "<?xml version='1.0' encoding='UTF-8'?>\n"
        xml += "<image w=\"\(doc.width)\" h=\"\(doc.height)\" version=\"0.0.3\" xres=\"\(Int(doc.dpi))\" yres=\"\(Int(doc.dpi))\">\n"
        xml += "<stack>\n"
        // OpenRaster lists layers top-most first.
        for (i, layer) in doc.layers.enumerated().reversed() {
            guard let png = ImageCodec.pngData(layer.surface) else { throw ImageCodecError.writeFailed("layer \(i)") }
            let path = "data/layer\(i).png"
            zip.add(name: path, data: png, compress: false)
            let opacity = String(format: "%.3f", Double(layer.opacity) / 255)
            xml += "<layer name=\"\(escape(layer.name))\" src=\"\(path)\" x=\"0\" y=\"0\" opacity=\"\(opacity)\" "
            xml += "visibility=\"\(layer.isVisible ? "visible" : "hidden")\" composite-op=\"\(layer.blendMode.oraName)\"/>\n"
        }
        xml += "</stack>\n</image>\n"
        zip.add(name: "stack.xml", data: Data(xml.utf8), compress: true)
        let flat = doc.flattened()
        if let merged = ImageCodec.pngData(flat) { zip.add(name: "mergedimage.png", data: merged, compress: false) }
        if let thumb = Resampler.thumbnail(of: flat, maxSize: 256), let t = ImageCodec.pngData(thumb) {
            zip.add(name: "Thumbnails/thumbnail.png", data: t, compress: false)
        }
        return zip.finish()
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    public static func load(url: URL) throws -> Document {
        let data = try Data(contentsOf: url)
        return try decode(data)
    }

    public static func decode(_ data: Data) throws -> Document {
        let zip = try ZipReader(data: data)
        guard let stack = try zip.read("stack.xml") else { throw ImageCodecError.unreadable("stack.xml missing") }
        let parser = StackParser()
        let xml = XMLParser(data: stack)
        xml.delegate = parser
        guard xml.parse(), parser.width > 0, parser.height > 0, parser.width <= 65535, parser.height <= 65535,
              parser.width * parser.height <= 1 << 30 else {
            throw ImageCodecError.unreadable("invalid stack.xml")
        }
        var layers: [BitmapLayer] = []
        for info in parser.layers.reversed() {
            let surface = Surface(width: parser.width, height: parser.height)
            if let png = try zip.read(info.src), let img = ImageCodec.surface(fromImageData: png) {
                surface.copy(from: img, to: IntPoint(x: info.x, y: info.y))
            }
            var props = LayerProperties(name: info.name)
            props.isVisible = info.visible
            props.opacity = clampToByte(info.opacity * 255)
            props.blendMode = BlendMode(oraName: info.compositeOp)
            layers.append(BitmapLayer(surface: surface, properties: props))
        }
        if layers.isEmpty { layers = [BitmapLayer(width: parser.width, height: parser.height, name: "Background")] }
        let doc = Document(width: parser.width, height: parser.height, layers: layers)
        if parser.dpi > 0 { doc.dpi = parser.dpi }
        return doc
    }

    private final class StackParser: NSObject, XMLParserDelegate {
        struct LayerInfo {
            var name: String
            var src: String
            var x: Int
            var y: Int
            var opacity: Double
            var visible: Bool
            var compositeOp: String
        }

        var width = 0, height = 0
        var dpi = 0.0
        var layers: [LayerInfo] = []
        /// Offsets of nested stacks (groups are flattened into the layer list).
        var stackOffsets: [(Int, Int)] = [(0, 0)]

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                    attributes a: [String: String] = [:]) {
            switch name {
            case "image":
                width = Int(a["w"] ?? "") ?? 0
                height = Int(a["h"] ?? "") ?? 0
                dpi = Double(a["xres"] ?? "") ?? 0
            case "stack":
                let base = stackOffsets.last ?? (0, 0)
                stackOffsets.append((base.0 + (Int(a["x"] ?? "") ?? 0), base.1 + (Int(a["y"] ?? "") ?? 0)))
            case "layer":
                let base = stackOffsets.last ?? (0, 0)
                layers.append(LayerInfo(name: a["name"] ?? "Layer", src: a["src"] ?? "",
                                        x: base.0 + (Int(a["x"] ?? "") ?? 0), y: base.1 + (Int(a["y"] ?? "") ?? 0),
                                        opacity: Double(a["opacity"] ?? "1") ?? 1,
                                        visible: (a["visibility"] ?? "visible") != "hidden",
                                        compositeOp: a["composite-op"] ?? "svg:src-over"))
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            if name == "stack" && stackOffsets.count > 1 { stackOffsets.removeLast() }
        }
    }
}

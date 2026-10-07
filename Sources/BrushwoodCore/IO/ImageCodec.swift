import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageCodecError: Error, LocalizedError {
    case unreadable(String)
    case unsupportedFormat(String)
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unreadable(let s): return "The file could not be read. \(s)"
        case .unsupportedFormat(let s): return "Unsupported file format: \(s)"
        case .writeFailed(let s): return "The file could not be saved. \(s)"
        }
    }
}

/// Options shown in the "Save Configuration" dialog.
public struct SaveOptions {
    /// 0...100 for lossy formats.
    public var quality: Int = 95
    /// 32 (with alpha), 24 or 8 (palette). 0 = automatic.
    public var bitDepth: Int = 0
    /// TGA run-length encoding.
    public var rleCompress: Bool = true

    public init() {}
}

/// A file type Brushwood can open or save.
public struct FileType: Hashable {
    public let id: String
    public let name: String
    public let extensions: [String]
    public let utType: String?
    public let canRead: Bool
    public let canWrite: Bool
    public let supportsLayers: Bool
    public let supportsAlpha: Bool
    public let hasQuality: Bool
    public let hasBitDepth: Bool

    public var primaryExtension: String { extensions[0] }

    public static let openRaster = FileType(id: "ora", name: "OpenRaster (layered)", extensions: ["ora"], utType: nil,
                                            canRead: true, canWrite: true, supportsLayers: true, supportsAlpha: true,
                                            hasQuality: false, hasBitDepth: false)
    public static let paintDotNet = FileType(id: "pdn", name: "Paint.NET Image", extensions: ["pdn"], utType: nil,
                                             canRead: true, canWrite: false, supportsLayers: true, supportsAlpha: true,
                                             hasQuality: false, hasBitDepth: false)
    public static let png = FileType(id: "png", name: "PNG", extensions: ["png"], utType: "public.png", canRead: true,
                                     canWrite: true, supportsLayers: false, supportsAlpha: true, hasQuality: false, hasBitDepth: true)
    public static let jpeg = FileType(id: "jpeg", name: "JPEG", extensions: ["jpg", "jpeg", "jpe", "jfif"],
                                      utType: "public.jpeg", canRead: true, canWrite: true, supportsLayers: false,
                                      supportsAlpha: false, hasQuality: true, hasBitDepth: false)
    public static let bmp = FileType(id: "bmp", name: "BMP", extensions: ["bmp", "dib"], utType: "com.microsoft.bmp",
                                     canRead: true, canWrite: true, supportsLayers: false, supportsAlpha: true,
                                     hasQuality: false, hasBitDepth: true)
    public static let gif = FileType(id: "gif", name: "GIF", extensions: ["gif"], utType: "com.compuserve.gif", canRead: true,
                                     canWrite: true, supportsLayers: false, supportsAlpha: true, hasQuality: false, hasBitDepth: false)
    public static let tiff = FileType(id: "tiff", name: "TIFF", extensions: ["tif", "tiff"], utType: "public.tiff",
                                      canRead: true, canWrite: true, supportsLayers: false, supportsAlpha: true,
                                      hasQuality: false, hasBitDepth: true)
    public static let tga = FileType(id: "tga", name: "TGA", extensions: ["tga"], utType: "com.truevision.tga-image",
                                     canRead: true, canWrite: true, supportsLayers: false, supportsAlpha: true,
                                     hasQuality: false, hasBitDepth: true)
    public static let dds = FileType(id: "dds", name: "DirectDraw Surface (DDS)", extensions: ["dds"],
                                     utType: "com.microsoft.dds", canRead: true, canWrite: true, supportsLayers: false,
                                     supportsAlpha: true, hasQuality: false, hasBitDepth: false)
    public static let webp = FileType(id: "webp", name: "WebP", extensions: ["webp"], utType: "org.webmproject.webp",
                                      canRead: true, canWrite: false, supportsLayers: false, supportsAlpha: true,
                                      hasQuality: true, hasBitDepth: false)
    public static let heic = FileType(id: "heic", name: "HEIC", extensions: ["heic", "heif"], utType: "public.heic",
                                      canRead: true, canWrite: true, supportsLayers: false, supportsAlpha: true,
                                      hasQuality: true, hasBitDepth: false)
    public static let avif = FileType(id: "avif", name: "AVIF", extensions: ["avif"], utType: "public.avif", canRead: true,
                                      canWrite: true, supportsLayers: false, supportsAlpha: true, hasQuality: true, hasBitDepth: false)
    public static let jpegXL = FileType(id: "jxl", name: "JPEG XL", extensions: ["jxl"], utType: "public.jpeg-xl",
                                        canRead: true, canWrite: false, supportsLayers: false, supportsAlpha: true,
                                        hasQuality: false, hasBitDepth: false)
    public static let ico = FileType(id: "ico", name: "Icon", extensions: ["ico"], utType: "com.microsoft.ico", canRead: true,
                                     canWrite: true, supportsLayers: false, supportsAlpha: true, hasQuality: false, hasBitDepth: false)
    public static let psd = FileType(id: "psd", name: "Photoshop (flattened)", extensions: ["psd"],
                                     utType: "com.adobe.photoshop-image", canRead: true, canWrite: false,
                                     supportsLayers: false, supportsAlpha: true, hasQuality: false, hasBitDepth: false)

    public static let all: [FileType] = [.openRaster, .paintDotNet, .png, .jpeg, .bmp, .gif, .tiff, .tga, .dds, .webp, .heic,
                                         .avif, .jpegXL, .ico, .psd]

    public static var readable: [FileType] { all.filter(\.canRead) }

    public static var writable: [FileType] {
        let dest = Set((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? [])
        return all.filter { $0.canWrite && ($0.utType == nil || dest.contains($0.utType!)) }
    }

    public static func forExtension(_ ext: String) -> FileType? {
        let e = ext.lowercased()
        return all.first { $0.extensions.contains(e) }
    }
}

public enum ImageCodec {
    /// Loads any supported image into a document.
    public static func load(url: URL) throws -> Document {
        let ext = url.pathExtension.lowercased()
        if ext == "ora" { return try OpenRaster.load(url: url) }
        if ext == "pdn" { return try PdnReader.load(url: url) }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ImageCodecError.unreadable(url.lastPathComponent)
        }
        let count = CGImageSourceGetCount(src)
        guard count > 0, let img = CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldAllowFloat: false] as CFDictionary),
              let surface = Surface(cgImage: orient(img, source: src)) else {
            throw ImageCodecError.unreadable(url.lastPathComponent)
        }
        let doc = Document(width: surface.width, height: surface.height,
                           layers: [BitmapLayer(surface: surface, properties: LayerProperties(name: "Background"))])
        if let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
           let dpi = props[kCGImagePropertyDPIWidth] as? Double, dpi > 0 {
            doc.dpi = dpi
        }
        return doc
    }

    /// Applies EXIF orientation so photos appear upright, like Paint.NET does.
    static func orient(_ img: CGImage, source: CGImageSource) -> CGImage {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let o = props[kCGImagePropertyOrientation] as? UInt32, o != 1,
              let orientation = CGImagePropertyOrientation(rawValue: o) else { return img }
        let w = img.width, h = img.height
        let swap = [.left, .leftMirrored, .right, .rightMirrored].contains(orientation)
        let dw = swap ? h : w, dh = swap ? w : h
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let ctx = CGContext(data: nil, width: dw, height: dh, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: Surface.sRGB, bitmapInfo: info) else { return img }
        var t = CGAffineTransform.identity
        let W = CGFloat(dw), H = CGFloat(dh)
        switch orientation {
        case .upMirrored: t = CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: W, ty: 0)
        case .down: t = CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: W, ty: H)
        case .downMirrored: t = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: H)
        case .left: t = CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: H)
        case .leftMirrored: t = CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0)
        case .right: t = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: W, ty: 0)
        case .rightMirrored: t = CGAffineTransform(a: 0, b: -1, c: -1, d: 0, tx: W, ty: H)
        default: break
        }
        ctx.concatenate(t)
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage() ?? img
    }

    /// Saves the document. Single-layer formats receive the flattened image.
    public static func save(_ doc: Document, to url: URL, type: FileType, options: SaveOptions) throws {
        if type == .openRaster {
            try OpenRaster.save(doc, to: url)
            return
        }
        guard type.canWrite, let ut = type.utType else { throw ImageCodecError.unsupportedFormat(type.name) }
        let data = try encode(doc.flattened(), type: ut, options: options, dpi: doc.dpi, supportsAlpha: type.supportsAlpha)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw ImageCodecError.writeFailed(error.localizedDescription)
        }
    }

    /// Encodes a flattened surface. Exposed for the save dialog's size preview.
    public static func encode(_ flat: Surface, type ut: String, options: SaveOptions, dpi: Double = 96,
                              supportsAlpha: Bool = true) throws -> Data {
        var surface = flat
        let wantsAlpha = supportsAlpha && options.bitDepth != 24
        if !wantsAlpha {
            // Formats without alpha are composited over white, like Paint.NET.
            let s = Surface(width: flat.width, height: flat.height, fill: .white)
            for y in 0..<s.height {
                Blender.blendRow(.normal, dst: s.row(y), src: flat.row(y), count: s.width, opacity: 255)
            }
            surface = s
        }
        guard let image = wantsAlpha ? surface.makeCGImage() : opaqueImage(surface) else {
            throw ImageCodecError.writeFailed("image conversion failed")
        }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data as CFMutableData, ut as CFString, 1, nil) else {
            throw ImageCodecError.unsupportedFormat(ut)
        }
        var props: [CFString: Any] = [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi]
        if ut == "public.jpeg" || ut == "public.heic" || ut == "public.avif" || ut == "org.webmproject.webp" {
            props[kCGImageDestinationLossyCompressionQuality] = Double(options.quality) / 100
        }
        if ut == "com.truevision.tga-image" {
            props[kCGImagePropertyTGADictionary] = [kCGImagePropertyTGACompression: options.rleCompress ? 1 : 0]
        }
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw ImageCodecError.writeFailed(ut) }
        return data as Data
    }

    static func opaqueImage(_ s: Surface) -> CGImage? {
        let data = NSMutableData(length: s.byteCount)!
        memcpy(data.mutableBytes, s.pixels, s.byteCount)
        guard let provider = CGDataProvider(data: data) else { return nil }
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        return CGImage(width: s.width, height: s.height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: s.width * 4,
                       space: Surface.sRGB, bitmapInfo: info, provider: provider, decode: nil, shouldInterpolate: true,
                       intent: .defaultIntent)
    }

    /// PNG data of a surface (used by OpenRaster and the clipboard).
    public static func pngData(_ s: Surface) -> Data? {
        try? encode(s, type: "public.png", options: SaveOptions())
    }

    public static func surface(fromImageData data: Data) -> Surface? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        return Surface(cgImage: img)
    }
}

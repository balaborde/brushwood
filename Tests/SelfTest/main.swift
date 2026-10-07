import CoreGraphics
import Foundation
import BrushwoodCore

struct BlendTests {
    func normalOpaqueReplaces() {
        let r = Blender.blend(.normal, ColorBgra(r: 10, g: 20, b: 30), ColorBgra(r: 200, g: 100, b: 50))
        expect(r == ColorBgra(r: 200, g: 100, b: 50))
    }

    func normalHalfAlphaOverOpaque() {
        let r = Blender.blend(.normal, .white, ColorBgra(r: 0, g: 0, b: 0, a: 128))
        expect(r.a == 255)
        expect(abs(Int(r.r) - 127) <= 1)
    }

    func overTransparentKeepsSource() {
        let src = ColorBgra(r: 50, g: 60, b: 70, a: 100)
        expect(Blender.blend(.multiply, .transparent, src) == src)
    }

    func multiplyAndScreen() {
        let a = ColorBgra(r: 128, g: 255, b: 0), b = ColorBgra(r: 128, g: 128, b: 255)
        let m = Blender.blend(.multiply, a, b)
        expect(m.r == 64 && m.g == 128 && m.b == 0)
        let s = Blender.blend(.screen, a, b)
        expect(s.g == 255 && s.b == 255)
    }

    func lerpToFullAndNone() {
        let a = ColorBgra(r: 1, g: 2, b: 3), b = ColorBgra(r: 200, g: 100, b: 50, a: 0)
        expect(Blender.lerpTo(a, b, coverage: 0) == a)
        expect(Blender.lerpTo(a, b, coverage: 255) == b)
    }
}

struct SurfaceTests {
    func cgImageRoundTripPreservesStraightAlpha() {
        let s = Surface(width: 4, height: 3)
        s[1, 1] = ColorBgra(r: 200, g: 40, b: 10, a: 255)
        s[2, 2] = ColorBgra(r: 0, g: 0, b: 255, a: 255)
        let img = s.makeCGImage()!
        let back = Surface(cgImage: img)!
        expect(back.contentEquals(s))
    }

    func copyRegionAndPaste() {
        let s = Surface(width: 10, height: 10, fill: .white)
        s.clear(.black, rect: IntRect(x: 2, y: 2, width: 3, height: 3))
        let part = s.copy(rect: IntRect(x: 1, y: 1, width: 5, height: 5))!
        expect(part[1, 1] == .black)
        expect(part[0, 0] == .white)
        let d = Surface(width: 10, height: 10)
        d.copy(from: part, to: IntPoint(x: 1, y: 1))
        expect(d[3, 3] == .black)
    }

    func resampleKeepsSolidColor() {
        let s = Surface(width: 37, height: 21, fill: ColorBgra(r: 10, g: 200, b: 90))
        for mode in ResamplingMode.allCases {
            let r = Resampler.resize(s, to: IntSize(width: 80, height: 9), mode: mode)
            expect(r.width == 80 && r.height == 9)
            let c = r[40, 4]
            expect(abs(Int(c.g) - 200) <= 1, "\(mode)")
        }
    }

    func rotationsAreInverse() {
        let s = Surface(width: 5, height: 3)
        for y in 0..<3 { for x in 0..<5 { s[x, y] = ColorBgra(r: UInt8(x * 40), g: UInt8(y * 80), b: 7) } }
        let r = Resampler.rotate90CCW(Resampler.rotate90CW(s))
        expect(r.contentEquals(s))
        expect(Resampler.rotate180(Resampler.rotate180(s)).contentEquals(s))
        expect(Resampler.flipHorizontal(Resampler.flipHorizontal(s)).contentEquals(s))
    }
}

struct SelectionTests {
    func rectMaskCoverage() {
        let sel = Selection.rect(CGRect(x: 2, y: 3, width: 4, height: 5))
        let m = sel.mask(width: 10, height: 10, antialias: false)
        var count = 0
        for y in 0..<10 { for x in 0..<10 where m[x, y] > 128 { count += 1 } }
        expect(count == 20)
        expect(m[2, 3] == 255)
        expect(m[1, 3] == 0)
    }

    func combineModes() {
        let a = Selection.rect(CGRect(x: 0, y: 0, width: 6, height: 6))
        let b = CGPath(rect: CGRect(x: 3, y: 3, width: 6, height: 6), transform: nil)
        func area(_ s: Selection?) -> Int {
            guard let s else { return 0 }
            let m = s.mask(width: 12, height: 12, antialias: false)
            var n = 0
            for y in 0..<12 { for x in 0..<12 where m[x, y] > 128 { n += 1 } }
            return n
        }
        expect(area(Selection.combine(a, with: b, mode: .union)) == 36 + 36 - 9)
        expect(area(Selection.combine(a, with: b, mode: .intersect)) == 9)
        expect(area(Selection.combine(a, with: b, mode: .exclude)) == 27)
        expect(area(Selection.combine(a, with: b, mode: .xor)) == 54)
        expect(area(Selection.combine(a, with: b, mode: .replace)) == 36)
    }

    func contourTracingMatchesMask() {
        let m = MaskSurface(width: 12, height: 9)
        // Ring with a hole and a diagonal neighbour.
        for y in 1..<7 { for x in 1..<7 { m[x, y] = 255 } }
        for y in 3..<5 { for x in 3..<5 { m[x, y] = 0 } }
        m[7, 7] = 255
        m[9, 2] = 255
        let sel = Selection.fromMask(m)!
        let back = sel.mask(width: 12, height: 9, antialias: false)
        for y in 0..<9 { for x in 0..<12 { expect((back[x, y] > 128) == (m[x, y] > 128), "\(x),\(y)") } }
    }
}

struct FloodFillTests {
    func contiguousStopsAtBorder() {
        let s = Surface(width: 10, height: 10, fill: .white)
        for y in 0..<10 { s[5, y] = .black }
        let m = FloodFill.fillMask(surface: s, seed: IntPoint(x: 1, y: 1), tolerance: 0.5, mode: .contiguous)
        expect(m[4, 9] == 255)
        expect(m[5, 5] == 0)
        expect(m[6, 5] == 0)
        let g = FloodFill.fillMask(surface: s, seed: IntPoint(x: 1, y: 1), tolerance: 0.5, mode: .global)
        expect(g[6, 5] == 255)
    }

    func toleranceZeroIsExact() {
        let s = Surface(width: 3, height: 1, fill: .white)
        s[1, 0] = ColorBgra(r: 254, g: 255, b: 255)
        let m = FloodFill.fillMask(surface: s, seed: IntPoint(x: 0, y: 0), tolerance: 0, mode: .global)
        expect(m[1, 0] == 0)
        expect(m[2, 0] == 255)
    }
}

struct DocumentTests {
    func compositeRespectsOpacityAndVisibility() {
        let doc = Document(width: 4, height: 4, background: .white)
        let top = BitmapLayer(width: 4, height: 4, name: "Top", fill: .black)
        top.opacity = 0
        doc.layers.append(top)
        expect(doc.flattened()[0, 0] == .white)
        top.opacity = 255
        expect(doc.flattened()[0, 0] == .black)
        top.isVisible = false
        expect(doc.flattened()[0, 0] == .white)
    }

    func historyUndoRedoPixels() {
        let doc = Document(width: 8, height: 8, background: .white)
        doc.history.reset(baseName: "New Image", icon: "new")
        let layer = doc.activeLayer
        let rect = IntRect(x: 2, y: 2, width: 3, height: 3)
        let before = layer.surface.copy(rect: rect)!
        layer.surface.clear(.black, rect: rect)
        let after = layer.surface.copy(rect: rect)!
        doc.history.push(PixelHistoryItem(name: "Fill", icon: "fill", layer: layer, rect: rect, before: before, after: after))
        expect(doc.isDirty)
        doc.history.undo()
        expect(layer.surface[3, 3] == .white)
        expect(!doc.isDirty)
        doc.history.redo()
        expect(layer.surface[3, 3] == .black)
    }

    func historyMemoryLimitDropsOldestSteps() {
        let doc = Document(width: 100, height: 100, background: .white)
        doc.history.reset(baseName: "New Image", icon: "new")
        doc.history.memoryLimit = 100 * 100 * 4 * 2 * 3  // room for three full-layer steps
        for i in 0..<6 {
            let layer = doc.activeLayer
            let before = layer.surface.copy(rect: doc.bounds)!
            layer.surface.clear(ColorBgra(r: UInt8(i * 40), g: 0, b: 0))
            doc.history.push(PixelHistoryItem(name: "Step \(i)", icon: "", layer: layer, rect: doc.bounds, before: before,
                                              after: layer.surface.copy(rect: doc.bounds)!))
        }
        expect(doc.history.items.count == 4, "kept \(doc.history.items.count)")
        expect(doc.history.items.last?.name == "Step 5")
        while doc.history.canUndo { doc.history.undo() }
        expect(doc.activeLayer.surface[0, 0].r == 80, "oldest reachable state")
    }

    func structuralHistoryRestoresLayers() {
        let doc = Document(width: 8, height: 8, background: .white)
        doc.history.reset(baseName: "New Image", icon: "new")
        let before = DocumentState(doc)
        doc.layers.append(BitmapLayer(width: 8, height: 8, name: "Layer 2"))
        doc.activeLayerIndex = 1
        doc.history.push(DocumentHistoryItem(name: "Add New Layer", icon: "addLayer", before: before, after: DocumentState(doc)))
        doc.history.undo()
        expect(doc.layers.count == 1)
        doc.history.redo()
        expect(doc.layers.count == 2)
        expect(doc.activeLayerIndex == 1)
    }
}

struct FileFormatTests {
    func zipRoundTrip() throws {
        let w = ZipWriter()
        let big = Data(String(repeating: "brushwood ", count: 500).utf8)
        w.add(name: "a.txt", data: Data("hello".utf8), compress: false)
        w.add(name: "dir/b.txt", data: big, compress: true)
        let r = try ZipReader(data: w.finish())
        expect(try r.read("a.txt") == Data("hello".utf8))
        expect(try r.read("dir/b.txt") == big)
    }

    func openRasterRoundTrip() throws {
        let doc = Document(width: 6, height: 5, background: .white)
        let l2 = BitmapLayer(width: 6, height: 5, name: "Ink & <stuff>")
        l2.surface[2, 2] = ColorBgra(r: 255, g: 0, b: 0, a: 200)
        l2.blendMode = .multiply
        l2.opacity = 128
        doc.layers.append(l2)
        let data = try OpenRaster.encode(doc)
        let back = try OpenRaster.decode(data)
        expect(back.layers.count == 2)
        expect(back.layers[1].name == "Ink & <stuff>")
        expect(back.layers[1].blendMode == .multiply)
        expect(abs(Int(back.layers[1].opacity) - 128) <= 1)
        expect(back.layers[1].surface[2, 2] == ColorBgra(r: 255, g: 0, b: 0, a: 200))
        expect(back.layers[0].surface[0, 0] == .white)
    }

    func pdnRoundTrip() throws {
        let doc = Document(width: 300, height: 700, background: .white)
        let l2 = BitmapLayer(width: 300, height: 700, name: "Ébauche “quotes” & more")
        for y in 0..<700 { for x in 0..<300 where (x + y) % 7 == 0 { l2.surface[x, y] = ColorBgra(r: UInt8(x % 256), g: UInt8(y % 256), b: 9, a: 200) } }
        l2.blendMode = .screen
        l2.opacity = 77
        l2.isVisible = false
        doc.layers.append(l2)
        let l3 = BitmapLayer(width: 300, height: 700, name: "Third")
        l3.blendMode = .screen
        doc.layers.append(l3)
        let data = try PdnWriter.encode(doc)
        let back = try PdnReader.decode(data)
        expect(back.width == 300 && back.height == 700)
        expect(back.layers.count == 3)
        expect(back.layers[1].name == "Ébauche “quotes” & more")
        expect(back.layers[1].blendMode == .screen && back.layers[2].blendMode == .screen)
        expect(back.layers[1].opacity == 77 && !back.layers[1].isVisible)
        for i in 0..<3 { expect(back.layers[i].surface.contentEquals(doc.layers[i].surface), "layer \(i) pixels") }
        if let dir = ProcessInfo.processInfo.environment["PDN_OUT"] {
            try data.write(to: URL(fileURLWithPath: dir + "/roundtrip.pdn"))
            if let u3 = try? PdnReader.load(url: URL(fileURLWithPath: dir + "/Untitled3.pdn")) {
                try PdnWriter.encode(u3).write(to: URL(fileURLWithPath: dir + "/Untitled3-rewritten.pdn"))
            }
        }
    }

    func gzipDecode() throws {
        // gzip of "abc" produced by Python's gzip module (mtime 0).
        let gz = Data([0x1F, 0x8B, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02, 0xFF, 0x4B, 0x4C, 0x4A, 0x06, 0x00,
                       0xC2, 0x41, 0x24, 0x35, 0x03, 0x00, 0x00, 0x00])
        expect(try Inflate.gzip(gz) == Data("abc".utf8))
    }
}

struct EffectTests {
    func run(_ e: Effect, _ src: Surface, _ values: EffectValues? = nil) -> Surface {
        let dst = src.clone()
        let env = EffectEnvironment(primaryColor: .black, secondaryColor: .white, selectionBounds: src.bounds, selectionMask: nil)
        EffectRunner.run(effect: e, src: src, dst: dst, values: values ?? EffectValues(e.parameters), env: env)
        return dst
    }

    func invertTwiceIsIdentity() {
        let s = Surface(width: 9, height: 7, fill: ColorBgra(r: 12, g: 99, b: 200, a: 77))
        let r = run(InvertColorsAdjustment(), run(InvertColorsAdjustment(), s))
        expect(r.contentEquals(s))
    }

    func blurOfSolidColorIsUnchanged() {
        let s = Surface(width: 30, height: 20, fill: ColorBgra(r: 40, g: 80, b: 120))
        let e = GaussianBlurEffect()
        var v = EffectValues(e.parameters)
        v["radius"] = .int(5)
        let r = run(e, s, v)
        expect(r[15, 10] == s[15, 10])
        expect(r[0, 0] == s[0, 0])
    }

    func everyEffectRunsWithDefaults() {
        let s = Surface(width: 24, height: 18)
        for y in 0..<18 { for x in 0..<24 { s[x, y] = ColorBgra(r: UInt8(x * 10), g: UInt8(y * 14), b: 128) } }
        let effects: [Effect] = [AutoLevelAdjustment(), BlackAndWhiteAdjustment(), BrightnessContrastAdjustment(),
                                 CurvesAdjustment(), HueSaturationAdjustment(), InvertColorsAdjustment(), LevelsAdjustment(),
                                 PosterizeAdjustment(), SepiaAdjustment(), InkSketchEffect(), OilPaintingEffect(),
                                 PencilSketchEffect(), BokehEffect(), FragmentEffect(), GaussianBlurEffect(), MotionBlurEffect(),
                                 RadialBlurEffect(), SurfaceBlurEffect(), UnfocusEffect(), ZoomBlurEffect(), BulgeEffect(),
                                 DentsEffect(), FrostedGlassEffect(), PixelateEffect(), PolarInversionEffect(),
                                 TileReflectionEffect(), TwistEffect(), AddNoiseEffect(), MedianEffect(), ReduceNoiseEffect(),
                                 DropShadowEffect(), FeatherEffect(), OutlineObjectEffect(), GlowEffect(), RedEyeRemovalEffect(),
                                 SharpenEffect(), SoftenPortraitEffect(), VignetteEffect(), CloudsEffect(), JuliaFractalEffect(),
                                 MandelbrotFractalEffect(), VoronoiEffect(), EdgeDetectEffect(), EmbossEffect(), OutlineEffect(),
                                 ReliefEffect()]
        for e in effects {
            let r = run(e, s)
            expect(r.width == 24, "\(e.name)")
        }
    }

    func curveIdentityTable() {
        let t = SplineCurve().table()
        expect(t[0] == 0 && t[128] == 128 && t[255] == 255)
        let c = SplineCurve(points: [CGPoint(x: 0, y: 0), CGPoint(x: 128, y: 200), CGPoint(x: 255, y: 255)]).table()
        expect(c[128] == 200)
    }

    func brightnessContrastNeutral() {
        let op = BrightnessContrastAdjustment.makeOp(brightness: 0, contrast: 0)
        let c = ColorBgra(r: 33, g: 140, b: 250, a: 9)
        expect(op(c) == c)
    }
}

// Minimal test harness: swift-testing needs Xcode to run, so the checks are plain functions.
var checks = 0
var failures = 0
var currentTest = ""

func expect(_ condition: @autoclosure () throws -> Bool, _ message: @autoclosure () -> String = "",
            file: StaticString = #fileID, line: UInt = #line) {
    checks += 1
    let ok = (try? condition()) ?? false
    if !ok {
        failures += 1
        print("✘ \(currentTest) \(file):\(line) \(message())")
    }
}

func run(_ name: String, _ body: () throws -> Void) {
    currentTest = name
    do { try body() } catch {
        failures += 1
        print("✘ \(name) threw \(error)")
    }
}

run("BlendTests.normalOpaqueReplaces") { BlendTests().normalOpaqueReplaces() }
run("BlendTests.normalHalfAlphaOverOpaque") { BlendTests().normalHalfAlphaOverOpaque() }
run("BlendTests.overTransparentKeepsSource") { BlendTests().overTransparentKeepsSource() }
run("BlendTests.multiplyAndScreen") { BlendTests().multiplyAndScreen() }
run("BlendTests.lerpToFullAndNone") { BlendTests().lerpToFullAndNone() }
run("SurfaceTests.cgImageRoundTripPreservesStraightAlpha") { SurfaceTests().cgImageRoundTripPreservesStraightAlpha() }
run("SurfaceTests.copyRegionAndPaste") { SurfaceTests().copyRegionAndPaste() }
run("SurfaceTests.resampleKeepsSolidColor") { SurfaceTests().resampleKeepsSolidColor() }
run("SurfaceTests.rotationsAreInverse") { SurfaceTests().rotationsAreInverse() }
run("SelectionTests.rectMaskCoverage") { SelectionTests().rectMaskCoverage() }
run("SelectionTests.combineModes") { SelectionTests().combineModes() }
run("SelectionTests.contourTracingMatchesMask") { SelectionTests().contourTracingMatchesMask() }
run("FloodFillTests.contiguousStopsAtBorder") { FloodFillTests().contiguousStopsAtBorder() }
run("FloodFillTests.toleranceZeroIsExact") { FloodFillTests().toleranceZeroIsExact() }
run("DocumentTests.compositeRespectsOpacityAndVisibility") { DocumentTests().compositeRespectsOpacityAndVisibility() }
run("DocumentTests.historyUndoRedoPixels") { DocumentTests().historyUndoRedoPixels() }
run("DocumentTests.historyMemoryLimitDropsOldestSteps") { DocumentTests().historyMemoryLimitDropsOldestSteps() }
run("DocumentTests.structuralHistoryRestoresLayers") { DocumentTests().structuralHistoryRestoresLayers() }
run("FileFormatTests.zipRoundTrip") { try FileFormatTests().zipRoundTrip() }
run("FileFormatTests.openRasterRoundTrip") { try FileFormatTests().openRasterRoundTrip() }
run("FileFormatTests.gzipDecode") { try FileFormatTests().gzipDecode() }
run("FileFormatTests.pdnRoundTrip") { try FileFormatTests().pdnRoundTrip() }
run("EffectTests.invertTwiceIsIdentity") { EffectTests().invertTwiceIsIdentity() }
run("EffectTests.blurOfSolidColorIsUnchanged") { EffectTests().blurOfSolidColorIsUnchanged() }
run("EffectTests.everyEffectRunsWithDefaults") { EffectTests().everyEffectRunsWithDefaults() }
run("EffectTests.curveIdentityTable") { EffectTests().curveIdentityTable() }
run("EffectTests.brightnessContrastNeutral") { EffectTests().brightnessContrastNeutral() }

// Optional: `swift run selftest <dir>` checks .pdn decoding and blend modes against Paint.NET reference renders
// (files from the pypdn project: FlattenBlendTest.pdn + Flatten*Test.png).
if CommandLine.arguments.count > 1 {
    let dir = URL(fileURLWithPath: CommandLine.arguments[1])
    run("PDN.untitled") {
        for name in ["Untitled.pdn", "Untitled2.pdn", "Untitled3.pdn"] {
            let doc = try PdnReader.load(url: dir.appendingPathComponent(name))
            expect(doc.width > 0 && doc.layers.count > 0, name)
            print("  \(name): \(doc.width)×\(doc.height), layers: " + doc.layers.map { "\($0.name) [\($0.blendMode.displayName), \($0.opacity)]" }.joined(separator: ", "))
        }
    }
    run("PDN.blendModes") {
        let doc = try PdnReader.load(url: dir.appendingPathComponent("FlattenBlendTest.pdn"))
        expect(doc.width == 800 && doc.height == 600, "size")
        let refs: [(BlendMode, String)] = [(.multiply, "flattenMultiplyTest.png"), (.additive, "FlattenAdditiveTest.png"),
            (.colorBurn, "FlattenColorBurnTest.png"), (.colorDodge, "FlattenColorDodgeTest.png"), (.reflect, "FlattenReflectTest.png"),
            (.glow, "FlattenGlowTest.png"), (.overlay, "FlattenOverlayTest.png"), (.difference, "FlattenDifferenceTest.png"),
            (.negation, "FlattenNegationTest.png"), (.lighten, "FlattenLightenTest.png"), (.darken, "FlattenDarkenTest.png"),
            (.screen, "FlattenScreenTest.png"), (.xor, "FlattenXORTest.png")]
        for (mode, file) in refs {
            guard let data = try? Data(contentsOf: dir.appendingPathComponent(file)),
                  let ref = ImageCodec.surface(fromImageData: data) else { expect(false, "missing \(file)"); continue }
            for (i, l) in doc.layers.enumerated() { l.isVisible = i == 0 || i == mode.rawValue }
            expect(doc.layers[mode.rawValue].blendMode == mode, "layer \(mode.rawValue) blend mode is \(doc.layers[mode.rawValue].blendMode)")
            let flat = doc.flattened()
            var maxDiff = 0, bad = 0
            for y in 0..<flat.height {
                for x in 0..<flat.width {
                    let a = flat[x, y], b = ref[x, y]
                    let d = max(abs(Int(a.r) - Int(b.r)), abs(Int(a.g) - Int(b.g)), abs(Int(a.b) - Int(b.b)))
                    maxDiff = max(maxDiff, d)
                    if d > 2 { bad += 1 }
                }
            }
            print("  \(mode.displayName): max diff \(maxDiff), pixels off by >2: \(bad)")
            expect(bad == 0, "\(mode.displayName) differs from Paint.NET reference (\(bad) pixels, max \(maxDiff))")
        }
    }
}

print(failures == 0 ? "✔ All \(checks) checks passed" : "✘ \(failures) of \(checks) checks failed")
exit(failures == 0 ? 0 : 1)

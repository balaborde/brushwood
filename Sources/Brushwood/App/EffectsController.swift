import AppKit
import BrushwoodCore

/// Menu contents of Adjustments and Effects, in Paint.NET order.
enum EffectsCatalog {
    static let adjustments: [() -> Effect] = [
        { AutoLevelAdjustment() }, { BlackAndWhiteAdjustment() }, { BrightnessContrastAdjustment() }, { CurvesAdjustment() },
        { HueSaturationAdjustment() }, { InvertColorsAdjustment() }, { LevelsAdjustment() }, { PosterizeAdjustment() },
        { SepiaAdjustment() },
    ]

    static let effects: [(EffectCategory, [() -> Effect])] = [
        (.artistic, [{ InkSketchEffect() }, { OilPaintingEffect() }, { PencilSketchEffect() }]),
        (.blurs, [{ BokehEffect() }, { FragmentEffect() }, { GaussianBlurEffect() }, { MedianEffect() }, { MotionBlurEffect() },
                  { RadialBlurEffect() }, { SketchBlurEffect() }, { SquareBlurEffect() }, { SurfaceBlurEffect() }, { ZoomBlurEffect() }]),
        (.color, [{ QuantizeEffect() }]),
        (.distort, [{ BulgeEffect() }, { CrystalizeEffect() }, { DentsEffect() }, { FrostedGlassEffect() }, { MorphologyEffect() },
                    { PixelateEffect() }, { PolarInversionEffect() }, { TileReflectionEffect() }, { TwistEffect() }]),
        (.noise, [{ AddNoiseEffect() }, { ReduceNoiseEffect() }]),
        (.object, [{ DropShadowEffect() }, { FeatherEffect() }, { OutlineObjectEffect() }]),
        (.photo, [{ GlowEffect() }, { RedEyeRemovalEffect() }, { SharpenEffect() }, { SoftenPortraitEffect() }, { StraightenEffect() },
                  { VignetteEffect() }]),
        (.render, [{ CloudsEffect() }, { JuliaFractalEffect() }, { MandelbrotFractalEffect() }, { TurbulenceEffect() }, { VoronoiEffect() }]),
        (.stylize, [{ EdgeDetectEffect() }, { EmbossEffect() }, { OutlineEffect() }, { ReliefEffect() }]),
    ]

    static func categoryIcon(_ c: EffectCategory) -> String {
        switch c {
        case .adjustment: return "sym.circle.lefthalf.filled"
        case .artistic: return "sym.paintpalette"
        case .blurs: return "sym.drop.halffull"
        case .color: return "sym.paintpalette"
        case .distort: return "sym.tornado"
        case .noise: return "sym.circle.grid.cross"
        case .object: return "sym.square.on.circle"
        case .photo: return "sym.camera.aperture"
        case .render: return "sym.cloud"
        case .stylize: return "sym.wand.and.rays"
        }
    }
}

/// Live preview of an effect on the active layer, rendered in the background into an override surface.
final class EffectPreviewSession {
    let workspace: DocumentWorkspace
    let effect: Effect
    let layerIndex: Int
    let src: Surface
    private(set) var dst: Surface
    let env: EffectEnvironment
    private weak var canvas: CanvasView?
    private weak var statusBar: StatusBar?
    private let queue = DispatchQueue(label: "app.brushwood.effect-preview", qos: .userInitiated)
    private var token: EffectRunner.Token?
    private var generation = 0
    private(set) var renderedValues: EffectValues?
    private var pendingValues: EffectValues?

    init(workspace: DocumentWorkspace, effect: Effect, canvas: CanvasView, statusBar: StatusBar, ignoreSelection: Bool = false) {
        self.workspace = workspace
        self.effect = effect
        self.canvas = canvas
        self.statusBar = statusBar
        let doc = workspace.document
        layerIndex = doc.activeLayerIndex
        src = doc.activeLayer.surface.clone()
        dst = src.clone()
        let app = AppEnvironment.shared
        env = EffectEnvironment(primaryColor: app.primaryColor, secondaryColor: app.secondaryColor,
                                selectionBounds: ignoreSelection ? doc.bounds : doc.selectionBoundsOrCanvas,
                                selectionMask: ignoreSelection ? nil : doc.selectionMask(antialias: app.tools.selectionClippingAntialiased))
        canvas.renderer?.overrides = [layerIndex: dst]
    }

    /// Starts (or restarts) rendering with new values.
    func update(_ values: EffectValues) {
        token?.cancel()
        let t = EffectRunner.Token()
        token = t
        generation += 1
        let gen = generation
        pendingValues = values
        let region = env.selectionBounds
        let total = max(1, region.area)
        var done = 0
        let lock = NSLock()
        statusBar?.setProgress(0)
        queue.async { [weak self] in
            guard let self else { return }
            let ok = EffectRunner.run(effect: self.effect, src: self.src, dst: self.dst, values: values, env: self.env, token: t) {
                band in
                lock.lock()
                done += band.area
                let fraction = Double(done) / Double(total)
                lock.unlock()
                performOnMain {
                    guard gen == self.generation else { return }
                    self.canvas?.renderer?.invalidate(band)
                    if let c = self.canvas { c.setNeedsDisplay(c.toView(band.cgRect).insetBy(dx: -1, dy: -1)) }
                    self.statusBar?.setProgress(fraction)
                }
            }
            performOnMain {
                guard gen == self.generation else { return }
                if ok { self.renderedValues = values }
                self.statusBar?.setProgress(nil)
            }
        }
    }

    /// Waits for the current render (re-rendering synchronously if needed) and commits it to the layer.
    func commit(values: EffectValues, name: String, icon: String) {
        token?.cancel()
        queue.sync {}
        if renderedValues != values {
            EffectRunner.run(effect: effect, src: src, dst: dst, values: values, env: env)
        }
        let doc = workspace.document
        let layer = doc.layers[layerIndex]
        let rect = env.selectionBounds.intersection(doc.bounds)
        canvas?.renderer?.overrides = [:]
        statusBar?.setProgress(nil)
        guard !rect.isEmpty, let before = src.copy(rect: rect), let after = dst.copy(rect: rect) else { return }
        layer.surface.copy(from: dst, rect: rect)
        doc.history.push(PixelHistoryItem(name: name, icon: icon, layer: layer, rect: rect, before: before, after: after))
        doc.invalidate(rect)
    }

    func cancel() {
        token?.cancel()
        generation += 1
        queue.sync {}
        canvas?.renderer?.overrides = [:]
        statusBar?.setProgress(nil)
        workspace.document.invalidate()
    }
}

/// Layers > Rotate / Zoom, implemented as an effect so it gets the standard live-preview dialog.
final class RotateZoomLayerEffect: Effect {
    override var name: String { "Rotate / Zoom" }
    override var parameters: [EffectParameter] {
        [
            .angle(id: "angle", label: "Angle", range: -180...180, defaultValue: 0),
            .offset(id: "pan", label: "Pan", defaultValue: .zero),
            .double(id: "zoom", label: "Zoom", range: 0.1...10, defaultValue: 1, decimals: 2),
            .checkbox(id: "tiling", label: "Tiling", defaultValue: false),
        ]
    }

    override func makeRenderer(src: Surface, values: EffectValues, env: EffectEnvironment) -> EffectRenderer {
        let b = env.selectionBounds
        let pan = values.point("pan")
        let c = CGPoint(x: CGFloat(b.x) + CGFloat(b.width) / 2, y: CGFloat(b.y) + CGFloat(b.height) / 2)
        let t = CGAffineTransform(translationX: c.x + pan.x * CGFloat(b.width) / 2, y: c.y + pan.y * CGFloat(b.height) / 2)
            .rotated(by: CGFloat(-values.double("angle") * .pi / 180))
            .scaledBy(x: CGFloat(values.double("zoom")), y: CGFloat(values.double("zoom")))
            .translatedBy(x: -c.x, y: -c.y)
        let inv = t.inverted()
        let tiling = values.bool("tiling")
        return ClosureRenderer { dst, rect in
            for y in rect.top..<rect.bottom {
                let d = dst.row(y)
                for x in rect.left..<rect.right {
                    var p = CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5).applying(inv)
                    if tiling {
                        p.x = p.x.truncatingRemainder(dividingBy: CGFloat(src.width))
                        if p.x < 0 { p.x += CGFloat(src.width) }
                        p.y = p.y.truncatingRemainder(dividingBy: CGFloat(src.height))
                        if p.y < 0 { p.y += CGFloat(src.height) }
                        d[x] = src.bilinearSample(Double(p.x), Double(p.y))
                    } else {
                        d[x] = src.bilinearSampleTransparentEdges(Double(p.x), Double(p.y))
                    }
                }
            }
        }
    }
}

extension MainWindowController {
    /// Applies an adjustment or effect, opening its dialog when it has parameters.
    func runEffect(factory: @escaping () -> Effect, historyIcon: String? = nil, repeatValues: EffectValues? = nil,
                   configure: ((Effect) -> Void)? = nil) {
        guard let ws = active else { return }
        commitPendingTool()
        let effect = factory()
        configure?(effect)
        let icon = historyIcon ?? (effect.category == .adjustment ? "history.adjustment" : "history.effect")
        let name = L(effect.name)
        let ignoreSelection = effect is RotateZoomLayerEffect
        let session = EffectPreviewSession(workspace: ws, effect: effect, canvas: canvas, statusBar: statusBar,
                                           ignoreSelection: ignoreSelection)
        if let repeatValues {
            session.commit(values: repeatValues, name: name, icon: icon)
            return
        }
        let remember: (EffectValues) -> Void = { [weak self] values in
            guard !(effect is RotateZoomLayerEffect) else { return }
            let snapshot = (effect as? CurvesAdjustment).map { c -> (Effect) -> Void in
                let mode = c.mode, l = c.luminosity, r = c.red, g = c.green, b = c.blue
                return { e in
                    guard let e = e as? CurvesAdjustment else { return }
                    e.mode = mode; e.luminosity = l; e.red = r; e.green = g; e.blue = b
                }
            } ?? (effect as? LevelsAdjustment).map { lv -> (Effect) -> Void in
                let levels = lv.levels
                return { e in (e as? LevelsAdjustment)?.levels = levels }
            }
            self?.lastEffect = (factory, values, snapshot)
        }
        if let curves = effect as? CurvesAdjustment {
            CurvesDialog.run(effect: curves, session: session, parent: window) { values in
                if let values {
                    session.commit(values: values, name: name, icon: icon)
                    remember(values)
                } else {
                    session.cancel()
                }
            }
        } else if let levels = effect as? LevelsAdjustment {
            LevelsDialog.run(effect: levels, session: session, parent: window) { values in
                if let values {
                    session.commit(values: values, name: name, icon: icon)
                    remember(values)
                } else {
                    session.cancel()
                }
            }
        } else if !effect.parameters.isEmpty {
            EffectDialog.run(effect: effect, session: session, parent: window) { values in
                if let values {
                    session.commit(values: values, name: name, icon: icon)
                    remember(values)
                } else {
                    session.cancel()
                }
            }
        } else {
            session.commit(values: EffectValues(), name: name, icon: icon)
            remember(EffectValues())
        }
    }

    @objc func applyEffectMenuItem(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? EffectFactoryBox else { return }
        runEffect(factory: box.factory)
    }

    @objc func repeatLastEffect(_ sender: Any?) {
        guard let last = lastEffect else { return }
        runEffect(factory: last.factory, repeatValues: last.values, configure: last.configure)
    }
}

/// Boxes an effect factory so it can travel in `NSMenuItem.representedObject`.
final class EffectFactoryBox: NSObject {
    let factory: () -> Effect
    init(_ f: @escaping () -> Effect) { factory = f }
}

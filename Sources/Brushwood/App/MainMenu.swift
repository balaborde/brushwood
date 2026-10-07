import AppKit
import BrushwoodCore

/// Builds the menu bar: Paint.NET's menus with Ctrl→⌘ shortcuts (adapted where macOS reserves a key).
enum MainMenu {
    static func build(delegate: AppDelegate) -> NSMenu {
        let main = NSMenu()
        main.addItem(submenu(appMenu(delegate)))
        main.addItem(submenu(fileMenu(delegate)))
        main.addItem(submenu(editMenu()))
        main.addItem(submenu(viewMenu()))
        main.addItem(submenu(imageMenu()))
        main.addItem(submenu(layersMenu()))
        main.addItem(submenu(adjustmentsMenu()))
        main.addItem(submenu(effectsMenu()))
        let window = windowMenu(delegate)
        main.addItem(submenu(window))
        NSApp.windowsMenu = window
        let help = helpMenu(delegate)
        main.addItem(submenu(help))
        NSApp.helpMenu = help
        return main
    }

    private static func submenu(_ m: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: m.title, action: nil, keyEquivalent: "")
        item.submenu = m
        return item
    }

    @discardableResult
    private static func add(_ menu: NSMenu, _ title: String, _ action: Selector?, _ key: String = "",
                            _ mods: NSEvent.ModifierFlags = [.command], icon: String? = nil, target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = key.isEmpty ? [] : mods
        if let icon { item.image = Icons.image(icon, size: 16) }
        item.target = target
        menu.addItem(item)
        return item
    }

    private static func appMenu(_ d: AppDelegate) -> NSMenu {
        let m = NSMenu(title: "Brushwood")
        add(m, L("About Brushwood"), #selector(AppDelegate.showAbout(_:)), target: d)
        m.addItem(.separator())
        add(m, L("Settings…"), #selector(AppDelegate.showSettings(_:)), ",", icon: "cmd.settings", target: d)
        m.addItem(.separator())
        let services = NSMenuItem(title: L("Services"), action: nil, keyEquivalent: "")
        let sm = NSMenu(title: L("Services"))
        services.submenu = sm
        NSApp.servicesMenu = sm
        m.addItem(services)
        m.addItem(.separator())
        add(m, L("Hide Brushwood"), #selector(NSApplication.hide(_:)), "h")
        add(m, L("Hide Others"), #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option])
        add(m, L("Show All"), #selector(NSApplication.unhideAllApplications(_:)))
        m.addItem(.separator())
        add(m, L("Quit Brushwood"), #selector(NSApplication.terminate(_:)), "q")
        return m
    }

    private static func fileMenu(_ d: AppDelegate) -> NSMenu {
        let m = NSMenu(title: L("File"))
        typealias W = MainWindowController
        add(m, L("New…"), #selector(W.newDocument(_:)), "n", icon: "cmd.new")
        add(m, L("Open…"), #selector(W.openDocument(_:)), "o", icon: "cmd.open")
        let recent = NSMenuItem(title: L("Open Recent"), action: nil, keyEquivalent: "")
        let rm = NSMenu(title: L("Open Recent"))
        rm.delegate = d
        recent.submenu = rm
        m.addItem(recent)
        m.addItem(.separator())
        add(m, L("Close"), #selector(W.closeDocument(_:)), "w")
        m.addItem(.separator())
        add(m, L("Save"), #selector(W.saveDocument(_:)), "s", icon: "cmd.save")
        add(m, L("Save As…"), #selector(W.saveDocumentAs(_:)), "s", [.command, .shift], icon: "cmd.saveAs")
        add(m, L("Save All"), #selector(W.saveAllDocuments(_:)), "s", [.command, .option])
        m.addItem(.separator())
        add(m, L("Print…"), #selector(W.printDocument(_:)), "p", icon: "cmd.print")
        return m
    }

    private static func editMenu() -> NSMenu {
        let m = NSMenu(title: L("Edit"))
        typealias W = MainWindowController
        add(m, L("Undo"), #selector(W.undo(_:)), "z", icon: "cmd.undo")
        add(m, L("Redo"), #selector(W.redo(_:)), "z", [.command, .shift], icon: "cmd.redo")
        let redoAlt = add(m, L("Redo"), #selector(W.redo(_:)), "y")
        redoAlt.isAlternate = false
        redoAlt.isHidden = true
        redoAlt.allowsKeyEquivalentWhenHidden = true
        m.addItem(.separator())
        add(m, L("Cut"), #selector(W.cut(_:)), "x", icon: "cmd.cut")
        add(m, L("Copy"), #selector(W.copy(_:)), "c", icon: "cmd.copy")
        add(m, L("Copy Merged"), #selector(W.copyMerged(_:)), "c", [.command, .shift], icon: "cmd.copyMerged")
        add(m, L("Paste"), #selector(W.paste(_:)), "v", icon: "cmd.paste")
        add(m, L("Paste Into New Layer"), #selector(W.pasteIntoNewLayer(_:)), "v", [.command, .shift])
        add(m, L("Paste Into New Image"), #selector(W.pasteIntoNewImage(_:)), "v", [.command, .option])
        add(m, L("Copy Selection"), #selector(W.copySelection(_:)), "c", [.command, .option, .shift])
        add(m, L("Paste Selection (Replace)"), #selector(W.pasteSelection(_:)), "v", [.command, .option, .shift])
        m.addItem(.separator())
        add(m, L("Erase Selection"), #selector(W.eraseSelection(_:)), "\u{8}", [], icon: "cmd.eraseSelection")
        add(m, L("Fill Selection"), #selector(W.fillSelection(_:)), "\u{8}", [.shift], icon: "cmd.fillSelection")
        add(m, L("Invert Selection"), #selector(W.invertSelection(_:)), "i", icon: "cmd.invertSelection")
        add(m, L("Select All"), #selector(W.selectAll(_:)), "a", icon: "cmd.selectAll")
        add(m, L("Deselect"), #selector(W.deselect(_:)), "d", icon: "cmd.deselect")
        m.addItem(.separator())
        add(m, L("Swap Colors"), #selector(W.swapColors(_:)), icon: "cmd.swapColors")
        add(m, L("Reset Colors"), #selector(W.resetColors(_:)))
        // Tools submenu mirrors the Tools window (letter shortcuts work on the canvas).
        let toolsItem = NSMenuItem(title: L("Tools"), action: nil, keyEquivalent: "")
        let tm = NSMenu(title: L("Tools"))
        for t in ToolKind.allCases {
            let item = add(tm, t.name, #selector(W.selectToolFromMenu(_:)), icon: t.icon)
            item.tag = t.rawValue
        }
        toolsItem.submenu = tm
        m.addItem(.separator())
        m.addItem(toolsItem)
        return m
    }

    private static func viewMenu() -> NSMenu {
        let m = NSMenu(title: L("View"))
        typealias W = MainWindowController
        add(m, L("Zoom In"), #selector(W.zoomIn(_:)), "+", icon: "cmd.zoomIn")
        let zi = add(m, L("Zoom In"), #selector(W.zoomIn(_:)), "=")
        zi.isHidden = true
        zi.allowsKeyEquivalentWhenHidden = true
        add(m, L("Zoom Out"), #selector(W.zoomOut(_:)), "-", icon: "cmd.zoomOut")
        add(m, L("Zoom to Window"), #selector(W.zoomToWindow(_:)), "b", icon: "cmd.zoomFit")
        add(m, L("Zoom to Selection"), #selector(W.zoomToSelection(_:)), "b", [.command, .shift])
        add(m, L("Actual Size"), #selector(W.actualSize(_:)), "0", icon: "cmd.actualSize")
        m.addItem(.separator())
        add(m, L("Pixel Grid"), #selector(W.togglePixelGrid(_:)), "'", icon: "cmd.grid")
        add(m, L("Rulers"), #selector(W.toggleRulers(_:)), "r", [.command, .option], icon: "cmd.rulers")
        let unitsItem = NSMenuItem(title: L("Units"), action: nil, keyEquivalent: "")
        let um = NSMenu(title: L("Units"))
        for u in MeasurementUnit.allCases {
            let item = add(um, u.name, #selector(W.setUnits(_:)))
            item.tag = u.rawValue
        }
        unitsItem.submenu = um
        m.addItem(unitsItem)
        m.addItem(.separator())
        add(m, L("Enter Full Screen"), #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control])
        return m
    }

    private static func imageMenu() -> NSMenu {
        let m = NSMenu(title: L("Image"))
        typealias W = MainWindowController
        add(m, L("Crop to Selection"), #selector(W.cropToSelection(_:)), "x", [.command, .shift], icon: "cmd.crop")
        add(m, L("Resize…"), #selector(W.resizeImage(_:)), "r", icon: "cmd.resize")
        add(m, L("Canvas Size…"), #selector(W.resizeCanvas(_:)), "r", [.command, .shift], icon: "cmd.canvasSize")
        m.addItem(.separator())
        add(m, L("Flip Horizontal"), #selector(W.flipImageHorizontal(_:)), icon: "cmd.flipH")
        add(m, L("Flip Vertical"), #selector(W.flipImageVertical(_:)), icon: "cmd.flipV")
        m.addItem(.separator())
        add(m, L("Rotate 90° Clockwise"), #selector(W.rotateImageCW(_:)), "h", [.command, .control], icon: "cmd.rotateCW")
        add(m, L("Rotate 90° Counter-clockwise"), #selector(W.rotateImageCCW(_:)), "g", icon: "cmd.rotateCCW")
        add(m, L("Rotate 180°"), #selector(W.rotateImage180(_:)), "j", icon: "cmd.rotate180")
        m.addItem(.separator())
        add(m, L("Flatten"), #selector(W.flatten(_:)), "f", [.command, .shift], icon: "cmd.flatten")
        return m
    }

    private static func layersMenu() -> NSMenu {
        let m = NSMenu(title: L("Layers"))
        typealias W = MainWindowController
        let pgUp = String(UnicodeScalar(NSPageUpFunctionKey)!), pgDn = String(UnicodeScalar(NSPageDownFunctionKey)!)
        add(m, L("Add New Layer"), #selector(W.addLayer(_:)), "n", [.command, .shift], icon: "layer.add")
        add(m, L("Delete Layer"), #selector(W.deleteLayer(_:)), "\u{8}", [.command, .shift], icon: "layer.delete")
        add(m, L("Duplicate Layer"), #selector(W.duplicateLayer(_:)), "d", [.command, .shift], icon: "layer.duplicate")
        add(m, L("Merge Layer Down"), #selector(W.mergeLayerDown(_:)), "m", [.command, .control], icon: "layer.merge")
        add(m, L("Toggle Layer Visibility"), #selector(W.toggleActiveLayerVisibility(_:)), ",", [.control, .command])
        add(m, L("Import From File…"), #selector(W.importFromFile(_:)), icon: "layer.import")
        m.addItem(.separator())
        add(m, L("Flip Horizontal"), #selector(W.flipLayerHorizontal(_:)), icon: "layer.flipH")
        add(m, L("Flip Vertical"), #selector(W.flipLayerVertical(_:)), icon: "layer.flipV")
        add(m, L("Rotate 180°"), #selector(W.rotateLayer180(_:)), icon: "cmd.rotate180")
        add(m, L("Rotate / Zoom…"), #selector(W.layerRotateZoom(_:)), "z", [.command, .option], icon: "layer.rotateZoom")
        m.addItem(.separator())
        add(m, L("Go to Top Layer"), #selector(W.selectTopLayer(_:)), pgUp, [.option, .command])
        add(m, L("Go to Layer Above"), #selector(W.selectLayerAbove(_:)), pgUp, [.option])
        add(m, L("Go to Layer Below"), #selector(W.selectLayerBelow(_:)), pgDn, [.option])
        add(m, L("Go to Bottom Layer"), #selector(W.selectBottomLayer(_:)), pgDn, [.option, .command])
        m.addItem(.separator())
        add(m, L("Move Layer to Top"), #selector(W.moveLayerToTop(_:)), pgUp, [.option, .shift, .command])
        add(m, L("Move Layer Up"), #selector(W.moveLayerUp(_:)), pgUp, [.option, .shift], icon: "layer.up")
        add(m, L("Move Layer Down"), #selector(W.moveLayerDown(_:)), pgDn, [.option, .shift], icon: "layer.down")
        add(m, L("Move Layer to Bottom"), #selector(W.moveLayerToBottom(_:)), pgDn, [.option, .shift, .command])
        m.addItem(.separator())
        add(m, L("Layer Properties…"), #selector(W.layerProperties(_:)), String(UnicodeScalar(NSF4FunctionKey)!), [],
            icon: "layer.properties")
        return m
    }

    private static func adjustmentsMenu() -> NSMenu {
        let m = NSMenu(title: L("Adjustments"))
        let keys: [String: (String, NSEvent.ModifierFlags)] = [
            "Auto-Level": ("l", [.command, .shift]), "Black and White": ("g", [.command, .shift]),
            "Brightness / Contrast": ("t", [.command, .shift]), "Invert Alpha": ("i", [.command, .option]),
            "Curves": ("m", [.command, .shift]), "Hue / Saturation": ("u", [.command, .shift]),
            "Invert Colors": ("i", [.command, .shift]), "Levels": ("l", [.command]), "Posterize": ("p", [.command, .shift]),
            "Sepia": ("e", [.command, .shift]),
        ]
        for factory in EffectsCatalog.adjustments {
            let e = factory()
            let k = keys[e.name]
            let item = add(m, L(e.name) + (e.showsDialog ? "…" : ""), #selector(MainWindowController.applyEffectMenuItem(_:)),
                           k?.0 ?? "", k?.1 ?? [], icon: "history.adjustment")
            item.representedObject = EffectFactoryBox(factory)
        }
        return m
    }

    private static func effectsMenu() -> NSMenu {
        let m = NSMenu(title: L("Effects"))
        add(m, L("Repeat"), #selector(MainWindowController.repeatLastEffect(_:)), "f")
        m.addItem(.separator())
        for (category, factories) in EffectsCatalog.effects {
            let sub = NSMenu(title: L(category.rawValue))
            for factory in factories {
                let e = factory()
                let item = add(sub, L(e.name) + (e.showsDialog ? "…" : ""), #selector(MainWindowController.applyEffectMenuItem(_:)))
                item.representedObject = EffectFactoryBox(factory)
            }
            let item = NSMenuItem(title: L(category.rawValue), action: nil, keyEquivalent: "")
            item.image = Icons.image(EffectsCatalog.categoryIcon(category), size: 16)
            item.submenu = sub
            m.addItem(item)
        }
        return m
    }

    private static func windowMenu(_ d: AppDelegate) -> NSMenu {
        let m = NSMenu(title: L("Window"))
        m.delegate = d
        typealias W = MainWindowController
        add(m, L("Tools"), #selector(W.toggleToolsWindow(_:)), String(UnicodeScalar(NSF5FunctionKey)!), [], icon: "window.tools")
        add(m, L("History"), #selector(W.toggleHistoryWindow(_:)), String(UnicodeScalar(NSF6FunctionKey)!), [], icon: "window.history")
        add(m, L("Layers"), #selector(W.toggleLayersWindow(_:)), String(UnicodeScalar(NSF7FunctionKey)!), [], icon: "window.layers")
        add(m, L("Colors"), #selector(W.toggleColorsWindow(_:)), String(UnicodeScalar(NSF8FunctionKey)!), [], icon: "window.colors")
        m.addItem(.separator())
        add(m, L("Next Image"), #selector(W.nextImage(_:)), "\t", [.control])
        add(m, L("Previous Image"), #selector(W.previousImage(_:)), "\t", [.control, .shift])
        m.addItem(.separator())
        add(m, L("Minimize"), #selector(NSWindow.performMiniaturize(_:)), "m")
        add(m, L("Zoom"), #selector(NSWindow.performZoom(_:)))
        m.addItem(.separator())
        // Open images are appended dynamically (menuNeedsUpdate).
        return m
    }

    private static func helpMenu(_ d: AppDelegate) -> NSMenu {
        let m = NSMenu(title: L("Help"))
        add(m, L("Brushwood Help"), #selector(AppDelegate.showHelp(_:)), "?", icon: "cmd.help", target: d)
        let f1 = add(m, L("Brushwood Help"), #selector(AppDelegate.showHelp(_:)), String(UnicodeScalar(NSF1FunctionKey)!), [], target: d)
        f1.isHidden = true
        f1.allowsKeyEquivalentWhenHidden = true
        add(m, L("Keyboard Shortcuts"), #selector(AppDelegate.showShortcuts(_:)), target: d)
        return m
    }
}

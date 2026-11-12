import AppKit
import OrbMotionKit
import PlaygroundLocalization
import ProjectionMotionKit

@MainActor
private final class HUDRenderData: HUDDataProviding {
    func sample(modules: Set<HUDModule>, now: Date) -> HUDDataSnapshot { .preview }
}

@MainActor
enum HUDPreviewExporter {
    static func export(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var files: [String] = []
        let cases: [(String, CGSize, HUDDensity, PlaygroundLanguage, Double, Bool, Bool)] = [
            ("standard-en", CGSize(width: 1280, height: 800), .standard, .english, 1, false, false),
            ("standard-zh", CGSize(width: 1280, height: 800), .standard, .simplifiedChinese, 1, false, false),
            ("compact-zh", CGSize(width: 1024, height: 640), .compact, .simplifiedChinese, 1, false, false),
            ("expanded-en", CGSize(width: 1600, height: 1000), .expanded, .english, 1, false, false),
            ("disabled-zh", CGSize(width: 1024, height: 640), .compact, .simplifiedChinese, 1, false, false),
            ("core-045", CGSize(width: 1280, height: 800), .standard, .english, 0.45, false, false),
            ("rings-065", CGSize(width: 1280, height: 800), .standard, .english, 0.65, false, false),
            ("borders-080", CGSize(width: 1280, height: 800), .standard, .english, 0.8, false, false),
            ("selected-zh", CGSize(width: 1280, height: 800), .standard, .simplifiedChinese, 1, true, false),
            ("detail-en", CGSize(width: 1280, height: 800), .standard, .english, 1, true, true),
            ("reduced-zh", CGSize(width: 1024, height: 640), .compact, .simplifiedChinese, 1, true, true)
        ]
        for (name, size, density, language, progress, selected, expanded) in cases {
            let dashboard = HUDDashboardController(provider: HUDRenderData())
            dashboard.config.density = density
            if name.hasPrefix("disabled") { dashboard.config.disabledModules.insert(.ai) }
            dashboard.setVisible(true)
            let view = HUDDashboardView(dashboard: dashboard)
            view.language = language
            let frame = CGRect(origin: .zero, size: size)
            let window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: true)
            window.title = "HUD render fixture"
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentView = view
            view.frame = frame
            var timeline = ProjectionTimeline()
            timeline.scrub(to: progress)
            let geometry = ProjectionGeometry(visibleFrame: frame, config: ProjectionConfig(), orb: ApprovedOrbParameters.value)
            view.render(geometry: geometry, timeline: timeline, reducedMotion: name.hasPrefix("reduced"))
            if selected, let target = HUDLayout(visibleSize: size, config: dashboard.config).moduleFrames[.performance] {
                view.performAction(at: CGPoint(x: target.midX, y: target.midY))
                guard dashboard.selected == .performance else { throw CocoaError(.validationMissingMandatoryProperty) }
                if expanded {
                    dashboard.expandSelection()
                } else {
                    dashboard.overview()
                    dashboard.select(.performance)
                }
                view.render(geometry: geometry, timeline: timeline, reducedMotion: name.hasPrefix("reduced"))
            }
            view.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.08))
            CATransaction.flush()
            func displayLayers(_ layer: CALayer) {
                layer.setNeedsDisplay()
                layer.displayIfNeeded()
                layer.sublayers?.forEach(displayLayers)
            }
            if let layer = view.layer { displayLayers(layer) }
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw CocoaError(.fileWriteUnknown) }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
            let filename = name + ".png"
            try png.write(to: directory.appendingPathComponent(filename), options: .atomic)
            files.append(filename)
            var layerText: [[String: Any]] = []
            func recordText(_ layer: CALayer, parentOpacity: Double) {
                let opacity = parentOpacity * Double(layer.opacity)
                if let text = layer as? CATextLayer, let string = text.string as? String, !string.isEmpty {
                    layerText.append(["text": string, "effective_opacity": opacity,
                                      "width": text.bounds.width, "height": text.bounds.height])
                }
                layer.sublayers?.forEach { recordText($0, parentOpacity: opacity) }
            }
            if let layer = view.layer { recordText(layer, parentOpacity: 1) }
            try JSONSerialization.data(withJSONObject: layerText, options: [.prettyPrinted, .sortedKeys])
                .write(to: directory.appendingPathComponent(name + "-text.json"), options: .atomic)
            let before = timeline
            dashboard.overview()
            dashboard.config.decorativeMotion = false
            guard timeline == before else { throw CocoaError(.validationMissingMandatoryProperty) }
            dashboard.setVisible(false)
            window.close()
        }
        let provider = NativeHUDDataProvider()
        _ = provider.sample(modules: Set(HUDModule.allCases), now: Date())
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        let native = provider.sample(modules: Set(HUDModule.allCases), now: Date())
        let report: [String: Any] = ["files": files, "render_data": "All render values are explicit Mock fixtures; real provider is sampled separately below.",
            "scope": "Offscreen native view renders in the retained preview. Not desktop screenshots or physical mouse tests.",
            "native_cpu": native.cpuUsage as Any? ?? NSNull(), "native_memory_used_bytes": native.memoryUsedBytes as Any? ?? NSNull(),
            "native_memory_total_bytes": native.memoryTotalBytes as Any? ?? NSNull(), "native_uptime": native.uptime,
            "native_upload_bytes_per_second": native.uploadBytesPerSecond as Any? ?? NSNull(),
            "native_download_bytes_per_second": native.downloadBytesPerSecond as Any? ?? NSNull(),
            "native_fixture": native.isFixture, "native_ai_mock": native.mockAI.isMock,
            "native_gpu": native.gpuUsage as Any? ?? NSNull(), "native_selection_probe_passed": true]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("manifest.json"), options: .atomic)
        print("Exported \(files.count) native HUD fixtures; component action probes and native data sample completed.")
    }
}

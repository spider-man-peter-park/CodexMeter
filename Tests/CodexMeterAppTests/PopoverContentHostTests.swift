import AppKit
import CodexMeterCore
import Foundation
import SwiftUI
import Testing
@testable import CodexMeterApp

@Suite(.serialized) @MainActor struct PopoverContentHostTests {
    private func fixture(popover: NSPopover? = nil,
                         onOpenSettings: @escaping () -> Void = {}, onOpenAbout: @escaping () -> Void = {}) throws
        -> (host: PopoverContentHost, defaults: UserDefaults, suite: String) {
        _ = NSApplication.shared
        let popover = popover ?? NSPopover()
        let suite = "io.github.codexmeter.popover-content-tests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.set("/private/tmp/codexmeter-popover-content-tests-empty", forKey: "codexHome")
        let model = AppModel(defaults: defaults,
            readQuota: { _ in throw AppServerError.queryFailed },
            readAccount: { _ in throw AppServerError.queryFailed })
        let updates = AppUpdates(defaults: defaults)
        return (PopoverContentHost(popover: popover, model: model, updates: updates,
            onOpenSettings: onOpenSettings, onOpenAbout: onOpenAbout), defaults, suite)
    }

    @Test func contentStaysUnallocatedUntilPreparedAndReusesTheSameController() throws {
        let popover = NSPopover()
        var settingsOpened = 0
        var aboutOpened = 0
        let (host, defaults, suite) = try fixture(popover: popover,
            onOpenSettings: { settingsOpened += 1 }, onOpenAbout: { aboutOpened += 1 })
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(host.controller == nil)
        #expect(popover.contentViewController == nil)
        #expect(!host.releaseIfHidden())

        let first = host.prepare(panelHeight: 640)
        #expect(host.controller === first)
        #expect(popover.contentViewController === first)
        #expect(first.rootView.panelHeight == 640)
        #expect(first.sizingOptions.contains(.preferredContentSize))
        let next = host.prepare(panelHeight: 720)
        #expect(next === first)
        #expect(next.rootView.panelHeight == 720)
        next.rootView.onOpenSettings()
        next.rootView.onOpenAbout()
        #expect(settingsOpened == 1)
        #expect(aboutOpened == 1)
    }

    @Test func releasingHiddenContentDetachesBothOwnersAndDeallocatesItsController() throws {
        let popover = NSPopover()
        let (host, defaults, suite) = try fixture(popover: popover)
        defer { defaults.removePersistentDomain(forName: suite) }
        weak var released: NSHostingController<PopoverView>?
        autoreleasepool {
            let controller = host.prepare(panelHeight: 640)
            _ = controller.view
            released = controller
        }
        #expect(released != nil)
        autoreleasepool { #expect(host.releaseIfHidden()) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        #expect(host.controller == nil)
        #expect(popover.contentViewController == nil)
        #expect(released == nil)
        #expect(!host.releaseIfHidden())
    }

    @Test func visiblePopoverContentCannotBeReleased() throws {
        let popover = PopoverVisibilityStub()
        let (host, defaults, suite) = try fixture(popover: popover)
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = host.prepare(panelHeight: 640)
        popover.simulatedShown = true
        #expect(!host.releaseIfHidden())
        #expect(host.controller === controller)
        #expect(popover.contentViewController === controller)
        popover.simulatedShown = false
        #expect(host.releaseIfHidden())
    }

    @Test func repeatedOpenCloseCyclesDoNotRetainPreviousControllers() throws {
        let popover = NSPopover()
        let (host, defaults, suite) = try fixture(popover: popover)
        defer { defaults.removePersistentDomain(forName: suite) }
        var previous: [WeakPopoverController] = []
        for cycle in 0..<20 {
            autoreleasepool {
                let controller = host.prepare(panelHeight: CGFloat(640 + cycle))
                _ = controller.view
                previous.append(WeakPopoverController(controller))
                #expect(host.releaseIfHidden())
            }
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        #expect(host.controller == nil)
        #expect(popover.contentViewController == nil)
        #expect(previous.allSatisfy { $0.value == nil })
    }
}

@MainActor private final class WeakPopoverController {
    weak var value: NSHostingController<PopoverView>?

    init(_ value: NSHostingController<PopoverView>) { self.value = value }
}

@MainActor private final class PopoverVisibilityStub: NSPopover {
    var simulatedShown = false
    override var isShown: Bool { simulatedShown }
}

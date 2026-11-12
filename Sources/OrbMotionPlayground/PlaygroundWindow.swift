import AppKit
import PlaygroundLocalization
import SwiftUI

enum PlaygroundWindow {
    static let identifier = NSUserInterfaceItemIdentifier("codexmeter.playground.debug")

    static var main: NSWindow? {
        let windows = NSApplication.shared.windows
        if let window = windows.first(where: { $0.identifier == identifier }) { return window }
        let titles = PlaygroundLanguage.allCases.flatMap {
            [$0.text("Orb Motion Playground"), $0.text("Projection Playground")]
        }
        return windows.first { titles.contains($0.title) }
    }

    static func update(mode: PlaygroundMode, language: PlaygroundLanguage) {
        DispatchQueue.main.async {
            guard let window = main else { return }
            window.identifier = identifier
            window.title = language.text(mode == .orb ? "Orb Motion Playground" : "Projection Playground")
        }
    }
}

private struct PlaygroundSnapshotKey: EnvironmentKey {
    static let defaultValue = false
}
private struct PlaygroundSnapshotPaneKey: EnvironmentKey {
    static let defaultValue = ""
}

extension EnvironmentValues {
    var playgroundSnapshot: Bool {
        get { self[PlaygroundSnapshotKey.self] }
        set { self[PlaygroundSnapshotKey.self] = newValue }
    }
    var playgroundSnapshotPane: String {
        get { self[PlaygroundSnapshotPaneKey.self] }
        set { self[PlaygroundSnapshotPaneKey.self] = newValue }
    }
}

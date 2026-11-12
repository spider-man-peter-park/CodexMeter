import SwiftUI
import PlaygroundLocalization

/// A deterministic, front-facing reactor independent of windows and playback ownership.
public struct EnergyOrb: View {
    public var parameters: OrbParameters
    public var progress: Double
    public var ambientTime: Double
    public var rotorTime: Double?
    public var reducedMotion: Bool
    @Environment(\.accessibilityReduceMotion) private var systemReducedMotion
    @Environment(\.playgroundLanguage) private var language

    public init(parameters: OrbParameters = OrbParameters(), progress: Double = 0,
                ambientTime: Double = 0, rotorTime: Double? = nil, reducedMotion: Bool = false) {
        self.parameters = parameters
        self.progress = progress
        self.ambientTime = ambientTime
        self.rotorTime = rotorTime
        self.reducedMotion = reducedMotion
    }

    public var body: some View {
        let configuration = parameters.sanitized
        let visibleProgress = progress.isFinite ? min(1, max(0, progress)) : 0
        OrbLayerSurface(parameters: configuration, progress: visibleProgress,
                        ambientTime: ambientTime, rotorTime: rotorTime,
                        reducedMotion: reducedMotion || systemReducedMotion, language: language)
            .frame(width: configuration.diameter + configuration.haloRadius * 2,
                   height: configuration.diameter + configuration.haloRadius * 2)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(language.text("Energy orb"))
            .accessibilityValue(language.format("%d percent activated", Int(visibleProgress * 100)))
    }
}

struct EnergyOrb_Previews: PreviewProvider {
    static var previews: some View {
        HStack(spacing: 32) {
            ForEach([0.0, 0.4, 1.0], id: \.self) { progress in
                VStack(spacing: 12) {
                    EnergyOrb(progress: progress)
                    Text("\(Int(progress * 100))%")
                        .font(.system(.caption, design: .monospaced)).foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .padding(40)
        .background(Color(red: 0.025, green: 0.045, blue: 0.065))
        .previewDisplayName("60 pt · idle / interrupted / charged")
    }
}

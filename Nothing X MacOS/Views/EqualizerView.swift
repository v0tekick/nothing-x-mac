import SwiftUI

struct EqualiserPreset: Identifiable {
    let id: Int
    let title: String
    let artwork: String

    static func available(for profile: NearbyAudioModel.EQ) -> [Self] {
        if profile.usesListeningMode {
            let cmf = [
                Self(id: 3, title: "Pop", artwork: "pop"),
                Self(id: 1, title: "Rock", artwork: "rock"),
                Self(id: 5, title: "Classical", artwork: "classical"),
                Self(id: 2, title: "Electronic", artwork: "electronic"),
                Self(id: 4, title: "Vocals", artwork: "vocals"),
            ]
            if let diracPreset = profile.diracPreset {
                return [Self(id: diracPreset, title: "Dirac Opteo", artwork: "dirac")] + cmf
            }
            return cmf
        }
        return [
            Self(id: 0, title: "Balanced", artwork: "balanced"),
            Self(id: 3, title: "More Bass", artwork: "bass"),
            Self(id: 2, title: "More Treble", artwork: "treble"),
            Self(id: 1, title: "Voice", artwork: "voice"),
        ]
    }

    static func selected(in bluetooth: BluetoothManager) -> Self? {
        guard bluetooth.isConnected, let id = bluetooth.equalizerPreset else { return nil }
        return available(for: bluetooth.equalizerProfile).first { $0.id == id }
    }

    var symbol: String {
        switch artwork {
        case "bass": return "speaker.wave.3"
        case "treble": return "waveform.path"
        case "voice", "vocals": return "mic"
        case "rock": return "guitars"
        case "classical": return "music.note"
        case "electronic": return "waveform"
        case "pop": return "music.quarternote.3"
        case "dirac": return "circle.hexagongrid"
        default: return "slider.horizontal.3"
        }
    }
}

struct EqualizerView: View {
    @ObservedObject private var bluetooth = BluetoothManager.shared

    var body: some View {
        NothingPage(title: "Equaliser") {
            VStack(alignment: .leading, spacing: 18) {
                if let selected = EqualiserPreset.selected(in: bluetooth) {
                    VStack(spacing: 6) {
                        Image(systemName: selected.symbol)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 168, height: 168)
                            .accessibilityHidden(true)
                        Text(selected.title).font(NothingType.title(23))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 10)
                }

                Text("Presets").font(NothingType.title(21))
                EqualiserPresetGrid(compact: false)
                if bluetooth.supportsBasicEQ {
                    BasicEqualiserEditor()
                        .id(bluetooth.selectedPairedAddress)
                }
                if !bluetooth.isConnected {
                    Text("Connect your device to change the equaliser.")
                        .font(NothingType.body(13))
                        .foregroundStyle(NothingPalette.muted)
                }
            }
        }
    }
}

private struct BasicEqualiserEditor: View {
    @ObservedObject private var bluetooth = BluetoothManager.shared
    @StateObject private var draft = EqualiserDraft()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Custom EQ").font(NothingType.title(21))
            if bluetooth.canEditBasicEQ, let current = bluetooth.basicEQ {
                ForEach(BasicAudioEQ.Band.allCases, id: \.self) { band in
                    HStack {
                        Slider(value: gainBinding(for: band, current: current), in: -6...6, step: 0.5) {
                            Text(band.title)
                        }
                        Text((draft.gains[band] ?? current.gains[band] ?? 0).formatted(.number.precision(.fractionLength(1))) + " dB")
                            .font(NothingType.mono(12))
                            .frame(minWidth: 62, alignment: .trailing)
                    }
                }
                Button("Apply Custom EQ") {
                    bluetooth.applyBasicEQ(current.gains.merging(draft.gains) { _, editedGain in editedGain })
                    draft.edited = false
                }
                .buttonStyle(GreyButton())
                .disabled(!draft.edited)
            } else if bluetooth.advancedEQEnabled == true {
                Text("Your device is using Advanced EQ. Change that profile in Nothing X on your phone.")
                    .foregroundStyle(NothingPalette.muted)
            } else if bluetooth.isConnected {
                Text("The device hasn’t returned a compatible three-band profile.")
                    .foregroundStyle(NothingPalette.muted)
            } else {
                Text("Connect your device to edit this profile.")
                    .foregroundStyle(NothingPalette.muted)
            }
        }
        .padding(18)
        .modifier(NothingCard())
        .onChange(of: bluetooth.basicEQ) { profile in
            if !draft.edited { draft.gains = profile?.gains ?? [:] }
        }
    }

    private func gainBinding(for band: BasicAudioEQ.Band, current: BasicAudioEQ) -> Binding<Double> {
        Binding(
            get: { draft.gains[band] ?? current.gains[band] ?? 0 },
            set: { value in
                draft.gains[band] = value
                draft.edited = true
            }
        )
    }

    private final class EqualiserDraft: ObservableObject {
        @Published var gains: [BasicAudioEQ.Band: Double] = [:]
        @Published var edited = false
    }
}

struct EqualiserPresetGrid: View {
    let compact: Bool
    @ObservedObject private var bluetooth = BluetoothManager.shared

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: compact ? 140 : 134), spacing: 8)], spacing: 8) {
            ForEach(EqualiserPreset.available(for: bluetooth.equalizerProfile)) { preset in
                let selected = bluetooth.isConnected && bluetooth.equalizerPreset == preset.id
                Button { bluetooth.setEqualizerPreset(preset.id) } label: {
                    if compact {
                        HStack(spacing: 8) {
                            artwork(preset, size: 24)
                            Text(preset.title).font(NothingType.title(13))
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .frame(minHeight: 44)
                        .background(selected ? NothingPalette.raised : NothingPalette.panel, in: RoundedRectangle(cornerRadius: 14))
                        .contentShape(Rectangle())
                    } else {
                        VStack(spacing: 9) {
                            artwork(preset, size: 68)
                            Text(preset.title).font(NothingType.title(16))
                        }
                        .frame(maxWidth: .infinity, minHeight: 115)
                        .background(selected ? NothingPalette.raised : NothingPalette.panel, in: RoundedRectangle(cornerRadius: 22))
                        .overlay(alignment: .topTrailing) {
                            if selected {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 14))
                                    .padding(12)
                                    .accessibilityHidden(true)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .disabled(!bluetooth.isConnected || bluetooth.equalizerPreset == nil)
            }
        }
        .opacity(bluetooth.isConnected ? 1 : 0.6)
    }

    private func artwork(_ preset: EqualiserPreset, size: CGFloat) -> some View {
        Image(systemName: preset.symbol)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

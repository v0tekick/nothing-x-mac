import SwiftUI

struct ControlsView: View {
    var body: some View {
        NothingPage(title: "Controls") {
            DeviceGestureEditor(showsArtwork: true)
        }
    }
}

struct DeviceGestureEditor: View {
    let showsArtwork: Bool
    @ObservedObject private var bluetooth = BluetoothManager.shared
    @State private var selectedPart: UInt8 = 2

    private var part: UInt8? {
        bluetooth.gestureSides.contains(selectedPart) ? selectedPart : bluetooth.gestureSides.first
    }

    var body: some View {
        VStack(spacing: 16) {
            if let part {
                if bluetooth.gestureSides.count > 1 {
                    Picker("Device controls", selection: Binding(get: { part }, set: { selectedPart = $0 })) {
                        ForEach(bluetooth.gestureSides, id: \.self) { side in
                            Text([2: "Left", 3: "Right", 4: "Case"][side] ?? "Device").tag(side)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 360)
                }
                if showsArtwork {
                    DeviceArtwork(name: bluetooth.deviceName, variant: bluetooth.selectedArtworkVariant,
                                  side: [2: EarBudSide.left, 3: .right][part], size: 158)
                }
                ControlMenuView(side: part)
            } else {
                Text("This device has no configurable gestures in Nothing X for Mac.")
                    .font(NothingType.body(14))
                    .foregroundStyle(NothingPalette.muted)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

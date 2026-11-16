import SwiftUI

struct ControlMenuView: View {
    let side: UInt8
    @ObservedObject private var bluetooth = BluetoothManager.shared

    var body: some View {
        let reported = bluetooth.gestures.filter { $0.id.side == side && bluetooth.gestureSlot(for: $0) != nil }
        VStack(alignment: .leading, spacing: 12) {
            if !bluetooth.isConnected {
                Text("Connect your device to change its controls.").foregroundStyle(NothingPalette.muted)
            } else if reported.isEmpty {
                Text("No editable controls reported yet.").foregroundStyle(NothingPalette.muted)
            } else {
                ForEach(reported) { gesture in
                    if let slot = bluetooth.gestureSlot(for: gesture) {
                        Picker(slot.title, selection: Binding(
                            get: { gesture.action },
                            set: { bluetooth.setGesture(gesture, action: $0) }
                        )) {
                            if !slot.actions.contains(gesture.action) {
                                Text("Current device setting").tag(gesture.action)
                            }
                            ForEach(slot.actions, id: \.self) { action in
                                Text(AudioGestureSlot.actionTitle(action)).tag(action)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
            }
        }
        .font(NothingType.body(14))
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(NothingCard())
    }
}

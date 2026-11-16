import SwiftUI

struct FindMyBudsView: View {
    @ObservedObject private var bluetooth = BluetoothManager.shared

    var body: some View {
        NothingPage(title: bluetooth.findDeviceTitle, subtitle: "Play a tone to locate your nearby device.") {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    DeviceArtwork(name: bluetooth.deviceName, variant: bluetooth.selectedArtworkVariant, size: 58)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(bluetooth.deviceName).font(NothingType.title(18))
                        Text(bluetooth.isConnected ? "Ready to play a tone" : bluetooth.connectionStatus)
                            .font(NothingType.body(13)).foregroundStyle(NothingPalette.muted)
                    }
                    Spacer()
                    Circle().fill(bluetooth.isConnected ? NothingPalette.green : NothingPalette.muted).frame(width: 7, height: 7)
                }
                .padding(17)
                .modifier(NothingCard())

                HStack(spacing: 10) {
                    ringButton(.left, label: bluetooth.canRingIndividualBuds ? "Play left" : "Play sound")
                    if bluetooth.canRingIndividualBuds {
                        ringButton(.right, label: "Play right")
                    }
                }
                Text("Remove your earbuds or headphones before playing a tone.")
                    .font(NothingType.body(13))
                    .foregroundStyle(NothingPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func ringButton(_ side: EarBudSide, label: String) -> some View {
        let ringing = bluetooth.ringingSide == side
        return Button {
            bluetooth.toggleRing(side: side)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: ringing ? "stop.fill" : "speaker.wave.2.fill")
                Text(ringing ? "Stop sound" : label)
            }
            .font(NothingType.title(16))
            .foregroundStyle(NothingPalette.ink)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(NothingPalette.text, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!bluetooth.isConnected || !bluetooth.supportsFindDevice)
    }
}

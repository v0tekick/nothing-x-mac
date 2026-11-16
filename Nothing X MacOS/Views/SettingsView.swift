import SwiftUI

struct SettingsView: View {
    let applyWindowPreset: (PopupWindowShape) -> Void

    @EnvironmentObject private var store: Store
    @ObservedObject private var bluetooth = BluetoothManager.shared
    @AppStorage(NearbyAudioPairing.preferenceKey) private var nearbyPairingPrompts = true

    var body: some View {
        NothingPage(title: "Settings") {
            VStack(alignment: .leading, spacing: 22) {
                settingSection("Window size presets") {
                    HStack(spacing: 10) {
                        ForEach(PopupWindowShape.allCases) { shape in
                            Button(shape.rawValue) {
                                store.windowShape = shape
                                applyWindowPreset(shape)
                            }
                            .buttonStyle(GreyButton())
                        }
                    }
                }

                settingSection("Bluetooth") {
                    Toggle("Nearby pairing prompts", isOn: $nearbyPairingPrompts)
                        .font(NothingType.title(17))
                        .toggleStyle(.switch)
                }
                .tint(NothingPalette.text)

                if bluetooth.supportsInEarDetection || bluetooth.supportsLowLatency {
                    settingSection("Audio") {
                        if bluetooth.supportsInEarDetection {
                            PreferenceRow(title: "In-ear Detection", detail: "Pause audio when the device is removed", asset: "nx-in-ear") {
                                Toggle("In-ear detection", isOn: Binding(get: { bluetooth.inEarDetection }, set: bluetooth.setInEarDetection))
                                    .labelsHidden().toggleStyle(.switch).disabled(!bluetooth.isConnected || !bluetooth.hasReportedInEarDetection)
                            }
                        }
                        if bluetooth.supportsInEarDetection && bluetooth.supportsLowLatency {
                            Divider().overlay(NothingPalette.line)
                        }
                        if bluetooth.supportsLowLatency {
                            PreferenceRow(title: "Low Latency Mode", detail: "Reduce wireless audio delay", asset: "nx-latency") {
                                Toggle("Low latency", isOn: Binding(get: { bluetooth.lowLatency }, set: bluetooth.setLowLatency))
                                    .labelsHidden().toggleStyle(.switch).disabled(!bluetooth.isConnected || !bluetooth.hasReportedLowLatency)
                            }
                        }
                    }
                    .tint(NothingPalette.text)
                }

                if bluetooth.supportsFindDevice {
                    settingSection("Device tools") {
                        NavigationLink(value: Destination.findMyBuds) {
                            SettingsLinkRow(title: bluetooth.findDeviceTitle, symbol: "waveform")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func settingSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(NothingType.title(20))
            VStack(spacing: 12, content: content)
                .padding(16)
                .modifier(NothingCard())
        }
    }
}

private struct PreferenceRow<Control: View>: View {
    let title: String
    let detail: String
    let asset: String
    @ViewBuilder let control: Control

    var body: some View {
        HStack(spacing: 16) {
            NothingIcon(asset: asset)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(NothingType.title(17))
                Text(detail).font(NothingType.body(13)).foregroundStyle(NothingPalette.muted)
            }
            Spacer()
            control
        }
    }
}

private struct SettingsLinkRow: View {
    let title: String
    let symbol: String
    var body: some View {
        HStack {
            Image(systemName: symbol).frame(width: 20).foregroundStyle(NothingPalette.muted)
            Text(title).font(NothingType.title(17))
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 10, weight: .medium)).foregroundStyle(NothingPalette.muted)
        }
        .frame(minHeight: 38)
        .contentShape(Rectangle())
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View { SettingsView { _ in }.environmentObject(Store()) }
}

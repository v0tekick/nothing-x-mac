import SwiftUI

struct BassEnhanceView: View {
    @ObservedObject private var bluetooth = BluetoothManager.shared

    var body: some View {
        NothingPage(title: "Bass Enhance") {
            if bluetooth.isConnected, let bass = bluetooth.bassEnhance {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text(bass.enabled ? "On" : "Off")
                        Spacer()
                        Button(bass.enabled ? "Turn Off" : "Turn On") {
                            bluetooth.setBassEnhanceEnabled(!bass.enabled)
                        }
                        .disabled(bass.level == nil)
                    }
                    if bass.level == nil {
                        Text("Choose a level to turn Bass Enhance on.")
                            .foregroundStyle(NothingPalette.muted)
                    }
                    HStack(spacing: 6) {
                        ForEach(1...bass.levelCount, id: \.self) { level in
                            Button { bluetooth.selectBassEnhanceLevel(level) } label: {
                                Text("\(level)")
                                    .foregroundStyle(bass.level == level ? NothingPalette.ink : NothingPalette.text)
                                    .frame(maxWidth: .infinity, minHeight: 34)
                                    .background(bass.level == level ? NothingPalette.text : NothingPalette.raised, in: Capsule())
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Bass level \(level)")
                            .accessibilityAddTraits(bass.level == level ? .isSelected : [])
                        }
                    }
                    .disabled(!bass.enabled && bass.level != nil)
                }
                .padding(18)
                .modifier(NothingCard())
            } else {
                FeatureAvailabilityText(isConnected: bluetooth.isConnected)
            }
        }
    }
}

struct PersonalSoundView: View {
    @ObservedObject private var bluetooth = BluetoothManager.shared

    var body: some View {
        NothingPage(title: "Personal Sound Profile") {
            VStack(alignment: .leading, spacing: 14) {
                if bluetooth.isConnected, bluetooth.personalSoundEnabled != nil {
                    Toggle("Use saved profile", isOn: Binding(
                        get: { bluetooth.personalSoundEnabled ?? false },
                        set: bluetooth.setPersonalSound
                    ))
                    .toggleStyle(.switch)
                } else {
                    FeatureAvailabilityText(isConnected: bluetooth.isConnected)
                }
                Text("Create or recalibrate your hearing profile in Nothing X on your phone.")
                    .foregroundStyle(NothingPalette.muted)
            }
            .padding(18)
            .modifier(NothingCard())
        }
    }
}

struct DualConnectionView: View {
    @ObservedObject private var bluetooth = BluetoothManager.shared

    var body: some View {
        NothingPage(title: "Dual Connection") {
            VStack(alignment: .leading, spacing: 16) {
                if bluetooth.isConnected, bluetooth.dualConnectionEnabled != nil {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Dual Connection", isOn: Binding(
                            get: { bluetooth.dualConnectionEnabled ?? false },
                            set: bluetooth.setDualConnection
                        ))
                        .toggleStyle(.switch)
                        Text("Connect up to two audio sources. Changing this setting may briefly disconnect your device.")
                            .font(NothingType.body(13))
                            .foregroundStyle(NothingPalette.muted)
                    }
                    .padding(18)
                    .modifier(NothingCard())
                    if bluetooth.dualConnectionEnabled == true {
                        HStack {
                            Text("Remembered Devices").font(NothingType.title(20))
                            Spacer()
                            Button("Refresh", action: bluetooth.refreshDualPeers)
                                .disabled(bluetooth.changingDualPeer || bluetooth.dualListInProgress)
                        }
                        if bluetooth.dualPeers.isEmpty {
                            Text(bluetooth.dualListInProgress ? "Waiting for remembered devices…" : "No remembered devices reported.")
                                .foregroundStyle(NothingPalette.muted)
                        }
                        ForEach(bluetooth.dualPeers) { peer in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(peer.isThisMac ? "This Mac" : peer.name)
                                    Text(peer.isConnected ? "Connected" : "Disconnected")
                                        .font(NothingType.body(13))
                                        .foregroundStyle(NothingPalette.muted)
                                }
                                Spacer()
                                if !peer.isThisMac {
                                    Button(peer.isConnected ? "Disconnect" : "Connect") {
                                        bluetooth.setDualPeerConnection(peer, connected: !peer.isConnected)
                                    }
                                    .disabled(bluetooth.changingDualPeer || (!peer.isConnected && connectedCount >= 2))
                                }
                            }
                            .padding(14)
                            .modifier(NothingCard())
                        }
                    }
                } else {
                    FeatureAvailabilityText(isConnected: bluetooth.isConnected)
                }
            }
        }
    }

    private var connectedCount: Int { bluetooth.dualPeers.filter(\.isConnected).count }
}

struct AudioDeviceSettingsView: View {
    @ObservedObject private var bluetooth = BluetoothManager.shared

    var body: some View {
        NothingPage(title: "Device Settings", subtitle: bluetooth.deviceName) {
            VStack(alignment: .leading, spacing: 16) {
                if bluetooth.supportsInEarDetection {
                    Toggle("In-ear Detection", isOn: Binding(
                        get: { bluetooth.inEarDetection }, set: bluetooth.setInEarDetection
                    ))
                    .disabled(!bluetooth.isConnected || !bluetooth.hasReportedInEarDetection)
                }
                if bluetooth.supportsLowLatency {
                    Toggle("Low Latency Mode", isOn: Binding(
                        get: { bluetooth.lowLatency }, set: bluetooth.setLowLatency
                    ))
                    .disabled(!bluetooth.isConnected || !bluetooth.hasReportedLowLatency)
                }
                if bluetooth.supportsFindDevice {
                    NavigationLink(bluetooth.findDeviceTitle, value: Destination.findMyBuds)
                        .buttonStyle(GreyButton())
                }
                NavigationLink("About this device", value: Destination.aboutDevice)
                    .buttonStyle(GreyButton())
            }
            .toggleStyle(.switch)
            .padding(18)
            .modifier(NothingCard())
        }
    }
}

struct AudioDeviceAboutView: View {
    @ObservedObject private var bluetooth = BluetoothManager.shared

    var body: some View {
        NothingPage(title: "About", subtitle: bluetooth.deviceName) {
            VStack(alignment: .leading, spacing: 14) {
                DeviceArtwork(name: bluetooth.deviceName, variant: bluetooth.selectedArtworkVariant, size: 132)
                    .frame(maxWidth: .infinity)
                LabeledContent("Model", value: bluetooth.deviceName)
                LabeledContent("Firmware", value: bluetooth.firmwareVersion ?? "—")
                LabeledContent("Connection", value: bluetooth.isConnected ? "Connected" : "Disconnected")
                Link("Nothing support and product guides", destination: URL(string: "https://support.nothing.tech/")!)
                    .buttonStyle(GreyButton())
            }
            .padding(18)
            .modifier(NothingCard())
        }
    }
}

private struct FeatureAvailabilityText: View {
    let isConnected: Bool

    var body: some View {
        Text(isConnected ? "This device hasn’t reported support for this setting." : "Connect your device to change this setting.")
            .font(NothingType.body(13))
            .foregroundStyle(NothingPalette.muted)
    }
}

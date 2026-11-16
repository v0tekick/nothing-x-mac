import AppKit
import SwiftUI

enum NothingPalette {
    static let ink = Color.black
    static let panel = Color(white: 28.0 / 255)
    static let raised = Color(white: 48.0 / 255)
    static let line = Color.white.opacity(0.13)
    static let text = Color(white: 242.0 / 255)
    static let muted = Color(white: 0.65)
    static let green = Color(red: 0.13, green: 0.71, blue: 0.39)
}

enum NothingType {
    static func dot(_ size: CGFloat, bold: Bool = false) -> Font {
        .system(size: size, weight: bold ? .bold : .medium, design: .monospaced)
    }

    static func title(_ size: CGFloat) -> Font { .system(size: size, design: .serif) }
    static func body(_ size: CGFloat) -> Font { .system(size: size) }
    static func mono(_ size: CGFloat) -> Font { .system(size: size, design: .monospaced) }
}

struct NothingCard: ViewModifier {
    var radius: CGFloat = 24

    func body(content: Content) -> some View {
        content.background(NothingPalette.panel, in: RoundedRectangle(cornerRadius: radius))
    }
}

struct NothingIcon: View {
    let asset: String
    var size: CGFloat = 24

    private var symbol: String {
        switch asset {
        case "nx-anc": return "ear"
        case "nx-transparency": return "ear.badge.waveform"
        case "nx-off": return "slash.circle"
        case "nx-in-ear": return "sensor"
        case "nx-bass-enhance": return "waveform.path"
        case "nx-personal-sound": return "waveform.circle"
        case "nx-dual-connection": return "link"
        case "nx-latency": return "bolt"
        case "nx-controls": return "hand.tap"
        default: return "waveform"
        }
    }

    var body: some View {
        Image(systemName: symbol)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct NothingRoundIcon: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .medium))
            .frame(width: 40, height: 40)
            .modifier(NothingGlassSurface(shape: Circle()))
            .contentShape(Circle())
    }
}

struct DeviceArtwork: View {
    let name: String
    var variant: NearbyAudioVariant? = nil
    var side: EarBudSide?
    let size: CGFloat

    var body: some View {
        let kind = variant?.model.kind ?? AudioCatalog.shared.model(named: name)?.kind ?? .earbuds
        Image(systemName: kind.symbol)
            .font(.system(size: size * 0.48, weight: .ultraLight))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    private var color: Color {
        switch variant?.colorName {
        case "White", "Light Grey": return NothingPalette.text
        case "Black", "Dark Grey": return NothingPalette.muted
        case "Orange", "Coral": return .orange
        case "Blue", "Turquoise": return .cyan
        case "Green", "Light Green": return .green
        case "Yellow": return .yellow
        case "Pink": return .pink
        default: return NothingPalette.muted
        }
    }
}

struct HomeView: View {
    @ObservedObject private var bluetooth = BluetoothManager.shared

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(maxWidth: 640)
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)

            ScrollView {
                VStack(spacing: 14) {
                    deviceStrip
                    if bluetooth.pairedAudioDevices.isEmpty {
                        emptyState
                    } else {
                        hero
                        if !bluetooth.availableNoiseModes.isEmpty { NoiseControlCard() }
                        featureCards
                    }
                }
                .frame(maxWidth: 640)
                .padding(.horizontal, 22)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity)
            }
        }
        .foregroundStyle(NothingPalette.text)
    }

    private var header: some View {
        HStack {
            Text("NOTHING X").font(NothingType.dot(25, bold: true))
            Spacer()
            SettingsButtonView()
        }
    }

    private var deviceStrip: some View {
        HStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                NothingGlassGroup {
                    HStack(spacing: 10) {
                        ForEach(bluetooth.pairedAudioDevices) { device in
                            let selected = bluetooth.selectedPairedAddress == device.address
                            Button { bluetooth.reconnect(to: device.address) } label: {
                                DeviceArtwork(name: device.name, variant: bluetooth.artworkVariant(for: device.address), size: 30)
                                    .frame(width: 46, height: 46)
                                    .modifier(NothingGlassSurface(
                                        shape: Circle(),
                                        fallback: selected ? NothingPalette.raised : NothingPalette.panel,
                                        tint: selected ? .white.opacity(0.23) : nil
                                    ))
                                    .overlay(alignment: .topTrailing) {
                                        if device.isBluetoothConnected {
                                            Circle().fill(NothingPalette.green).frame(width: 7, height: 7)
                                        }
                                    }
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(device.name))
                            .accessibilityAddTraits(selected ? .isSelected : [])
                            .help(device.name)
                        }
                    }
                    .padding(8)
                }
            }
            NavigationLink(value: Destination.devices) { NothingRoundIcon(symbol: "plus") }
                .buttonStyle(.plain)
                .accessibilityLabel("Manage devices")
                .help("Manage devices")
        }
    }

    private var hero: some View {
        VStack(spacing: 10) {
            DeviceArtwork(name: bluetooth.deviceName, variant: bluetooth.selectedArtworkVariant, size: 192)
                .background {
                    RadialGradient(
                        colors: [Color.white.opacity(0.13), .clear],
                        center: .center,
                        startRadius: 10,
                        endRadius: 144
                    )
                    .frame(width: 288, height: 288)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            Text(bluetooth.deviceName)
                .font(NothingType.title(32))
                .multilineTextAlignment(.center)
            if bluetooth.isConnected {
                BatteryReadout(compact: false).frame(maxWidth: 320)
            } else {
                Text(bluetooth.connectionStatus)
                    .font(NothingType.body(13))
                    .foregroundStyle(NothingPalette.muted)
                    .multilineTextAlignment(.center)
                Button("Connect") { bluetooth.reconnect() }
                    .buttonStyle(.plain)
                    .font(NothingType.title(15))
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 12)
    }

    private var featureCards: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
            if bluetooth.supportsBassEnhance {
                NavigationLink(value: Destination.bassEnhance) {
                    DeviceFeatureCard(title: "Bass Enhance", detail: bassSummary, asset: "nx-bass-enhance")
                }
            }
            if bluetooth.supportsPersonalSound {
                NavigationLink(value: Destination.personalSound) {
                    DeviceFeatureCard(title: "Personal Sound Profile", detail: status(bluetooth.personalSoundEnabled), asset: "nx-personal-sound")
                }
            }
            if bluetooth.supportsEqualizer {
                NavigationLink(value: Destination.equalizer) {
                    DeviceFeatureCard(title: "Equaliser", detail: EqualiserPreset.selected(in: bluetooth)?.title, asset: "nx-eq")
                }
            }
            if bluetooth.supportsGestureControls {
                NavigationLink(value: Destination.controls) {
                    DeviceFeatureCard(title: "Controls", detail: nil, asset: "nx-controls")
                }
            }
            if bluetooth.supportsLowLatency {
                Button { bluetooth.setLowLatency(!bluetooth.lowLatency) } label: {
                    let value = bluetooth.hasReportedLowLatency ? bluetooth.lowLatency : nil
                    DeviceFeatureCard(title: "Low Latency Mode", detail: status(value), asset: "nx-latency",
                                      toggleValue: bluetooth.isConnected ? value : nil)
                }
                .disabled(!bluetooth.isConnected || !bluetooth.hasReportedLowLatency)
            }
            if bluetooth.supportsDualConnection {
                NavigationLink(value: Destination.dualConnection) {
                    DeviceFeatureCard(title: "Dual Connection", detail: status(bluetooth.dualConnectionEnabled), asset: "nx-dual-connection")
                }
            }
            NavigationLink(value: Destination.audioDeviceSettings) {
                DeviceFeatureCard(title: "Device Settings", detail: nil, asset: "gearshape")
            }
            NavigationLink(value: Destination.aboutDevice) {
                DeviceFeatureCard(title: "About", detail: bluetooth.deviceName, asset: "info.circle")
            }
        }
        .buttonStyle(.plain)
    }

    private var bassSummary: String {
        if let bass = bluetooth.bassEnhance, bluetooth.isConnected {
            return bass.enabled ? bass.level.map { "On · Level \($0)" } ?? "On" : "Off"
        }
        return status(nil)
    }

    private func status(_ enabled: Bool?) -> String {
        guard bluetooth.isConnected else { return "Offline" }
        guard let enabled else { return "—" }
        return enabled ? "On" : "Off"
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            DeviceArtwork(name: "", size: 148)
            Text("Add a device").font(NothingType.title(30))
            Text("Pair your earbuds or headphones in Bluetooth Settings to see them here.")
                .font(NothingType.body(14))
                .foregroundStyle(NothingPalette.muted)
                .multilineTextAlignment(.center)
            NavigationLink("Manage devices", value: Destination.devices).buttonStyle(GreyButton())
                .frame(maxWidth: 240)
        }
        .padding(.vertical, 34)
    }
}

struct DevicesView: View {
    @ObservedObject private var bluetooth = BluetoothManager.shared

    var body: some View {
        NothingPage(title: "Devices") {
            VStack(alignment: .leading, spacing: 12) {
                if bluetooth.pairedAudioDevices.isEmpty {
                    Text("No paired audio devices")
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .modifier(NothingCard())
                } else {
                    ForEach(bluetooth.pairedAudioDevices) { device in
                        HStack(spacing: 14) {
                            let variant = bluetooth.artworkVariant(for: device.address)
                            Button { bluetooth.reconnect(to: device.address) } label: {
                                HStack(spacing: 14) {
                                    DeviceArtwork(name: device.name, variant: variant, size: 44)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(device.name).font(NothingType.title(18))
                                        Text(bluetooth.isConnected && bluetooth.selectedPairedAddress == device.address
                                             ? "Connected" : device.isBluetoothConnected ? "Bluetooth connected" : "Paired")
                                            .font(NothingType.body(13))
                                            .foregroundStyle(NothingPalette.muted)
                                    }
                                    Spacer()
                                    Text("Connect").font(NothingType.body(13))
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if let model = variant?.model ?? NearbyAudioModel.allCases.first(where: { $0.matches(name: device.name) }) {
                                Menu {
                                    Picker("Device color", selection: Binding(
                                        get: { bluetooth.artworkVariant(for: device.address) },
                                        set: { bluetooth.setArtworkVariant($0, for: device.address) }
                                    )) {
                                        Text("Unknown").tag(nil as NearbyAudioVariant?)
                                        ForEach(NearbyAudioVariant.allCases.filter { $0.model == model }) { option in
                                            Text(option.colorName).tag(Optional(option))
                                        }
                                    }
                                } label: {
                                    Label(variant?.colorName ?? "Set Color", systemImage: "paintpalette")
                                }
                                .menuStyle(.borderlessButton)
                                .fixedSize()
                                .accessibilityLabel("Device color")
                            }
                        }
                        .padding(14)
                        .modifier(NothingCard())
                    }
                }
                Button("Open Bluetooth Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") {
                        NSWorkspace.shared.open(url)
                    }
                }.buttonStyle(GreyButton())
                Button("Refresh devices") { bluetooth.refreshPairedDevices() }
                    .buttonStyle(GreyButton())
            }
        }
    }
}

struct NothingPage<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let subtitle: String?
    let content: Content

    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: { NothingRoundIcon(symbol: "arrow.left") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")
                Spacer()
            }
            .frame(maxWidth: 640)
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title).font(NothingType.title(34))
                        if let subtitle {
                            Text(subtitle)
                                .font(NothingType.body(14))
                                .foregroundStyle(NothingPalette.muted)
                        }
                    }
                    content.frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: 640, alignment: .leading)
                .padding(.horizontal, 22)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity)
            }
        }
        .font(NothingType.body(15))
        .foregroundStyle(NothingPalette.text)
        .navigationBarBackButtonHidden(true)
    }
}

private struct DeviceFeatureCard: View {
    let title: String
    let detail: String?
    let asset: String
    var toggleValue: Bool? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top) {
                Text(title).font(NothingType.title(20))
                Spacer()
                if toggleValue == nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(NothingPalette.muted)
                }
            }
            if let detail {
                Text(detail).font(NothingType.body(13)).foregroundStyle(NothingPalette.muted)
            }
            Spacer(minLength: 10)
            HStack {
                if let toggleValue {
                    Capsule()
                        .fill(toggleValue ? NothingPalette.text : NothingPalette.muted)
                        .frame(width: 34, height: 20)
                        .overlay(alignment: toggleValue ? .trailing : .leading) {
                            Circle().fill(NothingPalette.ink).frame(width: 16, height: 16).padding(2)
                        }
                        .accessibilityHidden(true)
                }
                Spacer()
                if asset.hasPrefix("nx-") {
                    NothingIcon(asset: asset)
                } else {
                    Image(systemName: asset).font(.system(size: 21))
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 114, alignment: .topLeading)
        .modifier(NothingCard())
        .contentShape(Rectangle())
    }
}

struct NoiseControlCard: View {
    @ObservedObject private var bluetooth = BluetoothManager.shared
    private var strengths: [String] { bluetooth.availableANCStrengths }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Noise Control").font(NothingType.title(21))
            NoiseModePicker(compact: false)
            if bluetooth.isConnected && bluetooth.noiseMode == "anc" && strengths.count > 1 {
                HStack(spacing: 4) {
                    ForEach(strengths, id: \.self) { strength in
                        let selected = bluetooth.ancStrength == strength
                        Button { bluetooth.setNoiseControl("anc", strength: strength) } label: {
                            Text(strength.capitalized)
                                .font(NothingType.body(12))
                                .foregroundStyle(selected ? NothingPalette.ink : NothingPalette.text)
                                .frame(maxWidth: .infinity, minHeight: 32)
                                .background(selected ? NothingPalette.text : .clear, in: Capsule())
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                .padding(3)
                .background(NothingPalette.raised, in: Capsule())
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Noise cancellation strength")
            }
        }
        .padding(16)
        .modifier(NothingCard())
    }
}

struct NoiseModePicker: View {
    let compact: Bool
    @ObservedObject private var bluetooth = BluetoothManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var options: [(String, String, String)] {
        [
            ("Noise cancellation", "nx-anc", "anc"),
            ("Transparency", "nx-transparency", "transparency"),
            ("Off", "nx-off", "off"),
        ].filter { bluetooth.availableNoiseModes.contains($0.2) }
    }

    private var selectedIndex: Int? {
        guard bluetooth.isConnected, bluetooth.hasReportedNoiseControl else { return nil }
        return options.firstIndex { $0.2 == bluetooth.noiseMode }
    }

    var body: some View {
        Group {
            if compact {
                segments
                    .background { selectionIndicator }
                    .modifier(NothingGlassSurface(shape: Capsule(), fallback: NothingPalette.raised, interactive: false))
            } else {
                NothingGlassGroup { segments }
            }
        }
        .opacity(bluetooth.isConnected ? 1 : 0.54)
    }

    private var segments: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.2) { option in
                let selected = bluetooth.isConnected && bluetooth.hasReportedNoiseControl && bluetooth.noiseMode == option.2
                Button {
                    bluetooth.setNoiseControl(option.2, strength: bluetooth.ancStrength)
                } label: {
                    VStack(spacing: 6) {
                        noiseIcon(option.1, selected: selected)
                        if !compact {
                            Text(option.0)
                                .font(NothingType.body(12))
                                .foregroundStyle(selected ? NothingPalette.text : NothingPalette.muted)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: compact ? 44 : 86)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(option.0))
                .accessibilityAddTraits(selected ? .isSelected : [])
                .disabled(!bluetooth.isConnected || !bluetooth.hasReportedNoiseControl)
            }
        }
    }

    private func noiseIcon(_ asset: String, selected: Bool) -> some View {
        let icon = NothingIcon(asset: asset, size: 22)
            .foregroundStyle(selected ? NothingPalette.ink : NothingPalette.text)

        return Group {
            if compact {
                icon
            } else if selected {
                icon.frame(width: 48, height: 48)
                    .background(NothingPalette.text, in: Circle())
            } else {
                icon.frame(width: 48, height: 48)
                    .modifier(NothingGlassSurface(shape: Circle(), fallback: NothingPalette.raised))
            }
        }
    }

    private var selectionIndicator: some View {
        GeometryReader { geometry in
            if let selectedIndex {
                let width = geometry.size.width / CGFloat(options.count)
                Capsule()
                    .fill(NothingPalette.text)
                    .padding(3)
                    .frame(width: width)
                    .offset(x: width * CGFloat(selectedIndex))
                    .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.85), value: selectedIndex)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct BatteryReadout: View {
    let compact: Bool
    @ObservedObject private var bluetooth = BluetoothManager.shared

    var body: some View {
        HStack(spacing: compact ? 12 : 20) {
            if let kind = bluetooth.audioModel?.kind, kind != .earbuds {
                cell("Battery", value: bluetooth.stereoBattery ?? bluetooth.leftBattery ?? bluetooth.caseBattery)
            } else {
                cell("L", value: bluetooth.leftBattery)
                cell("C", value: bluetooth.caseBattery)
                cell("R", value: bluetooth.rightBattery)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func cell(_ label: String, value reportedValue: Int?) -> some View {
        let value = bluetooth.isConnected ? reportedValue : nil
        return VStack(spacing: 6) {
            Text(value.map { "\($0)%  \(label)" } ?? "–  \(label)")
                .font(NothingType.mono(compact ? 12 : 15))
                .foregroundStyle(value == nil ? NothingPalette.muted : NothingPalette.text)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(NothingPalette.raised)
                    Capsule().fill(NothingPalette.text)
                        .frame(width: proxy.size.width * CGFloat(value ?? 0) / 100)
                }
            }
            .frame(height: 3)
        }
        .frame(maxWidth: compact ? .infinity : label == "Battery" ? 160 : 112)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(["L": "Left", "C": "Case", "R": "Right"][label] ?? label))
        .accessibilityValue(Text(value.map { "\($0) percent" } ?? "Unavailable"))
    }
}

struct MenuBarDashboardView: View {
    let openMainWindow: () -> Void
    let quitApp: () -> Void
    @ObservedObject private var bluetooth = BluetoothManager.shared

    var body: some View {
        VStack(spacing: 12) {
            NothingGlassGroup {
                HStack(spacing: 9) {
                    DeviceArtwork(name: bluetooth.deviceName, variant: bluetooth.selectedArtworkVariant, size: 35)
                        .frame(width: 44, height: 44)
                        .background(NothingPalette.panel, in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        deviceMenu
                        Text(bluetooth.isConnected ? "Connected" : bluetooth.selectedDeviceIsBluetoothConnected ? "Bluetooth connected" : "Disconnected")
                            .font(NothingType.body(11))
                            .foregroundStyle(NothingPalette.muted)
                    }
                    Spacer(minLength: 2)
                    Button(action: openMainWindow) { NothingRoundIcon(symbol: "gearshape") }
                        .buttonStyle(.plain).help("Open Nothing X").accessibilityLabel("Open Nothing X")
                    Button { bluetooth.reconnect() } label: { NothingRoundIcon(symbol: "arrow.clockwise") }
                        .buttonStyle(.plain).help("Refresh connection").accessibilityLabel("Refresh connection")
                }
            }

            BatteryReadout(compact: true)
                .padding(.horizontal, 5)

            if !bluetooth.availableNoiseModes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Noise Control").font(NothingType.title(16))
                    NoiseModePicker(compact: true)
                }
                .padding(11)
                .modifier(NothingCard(radius: 18))
            }

            NothingGlassGroup {
                HStack(spacing: 8) {
                    if bluetooth.supportsEqualizer {
                        NavigationLink(value: Destination.equalizer) { quickLink("Equaliser", asset: "nx-eq") }
                    }
                    if bluetooth.supportsGestureControls || bluetooth.supportsLowLatency || bluetooth.supportsInEarDetection {
                        NavigationLink(value: Destination.controls) { quickLink("Controls", asset: "nx-controls") }
                    }
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 12) {
                Text("NOTHING X").font(NothingType.dot(13))
                Spacer()
                Button("Close App", action: quitApp)
                Button("Open App ↗", action: openMainWindow)
            }
            .font(NothingType.body(12))
            .buttonStyle(.plain)
            .foregroundStyle(NothingPalette.muted)
        }
        .padding(16)
        .frame(width: 358, height: 330)
        .foregroundStyle(NothingPalette.text)
    }

    private var deviceMenu: some View {
        Menu {
            ForEach(bluetooth.pairedAudioDevices) { device in
                Button { bluetooth.reconnect(to: device.address) } label: {
                    if bluetooth.selectedPairedAddress == device.address {
                        Label(device.name, systemImage: "checkmark")
                    } else {
                        Text(device.name)
                    }
                }
            }
            Button("Refresh devices") { bluetooth.refreshPairedDevices() }
        } label: {
            Text(bluetooth.deviceName)
                .font(NothingType.title(15))
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
    }

    private func quickLink(_ title: String, asset: String) -> some View {
        HStack(spacing: 7) {
            NothingIcon(asset: asset, size: 18)
            Text(title).font(NothingType.title(14))
        }
        .frame(maxWidth: .infinity, minHeight: 38)
        .modifier(NothingGlassSurface(shape: RoundedRectangle(cornerRadius: 14)))
        .contentShape(Rectangle())
    }
}

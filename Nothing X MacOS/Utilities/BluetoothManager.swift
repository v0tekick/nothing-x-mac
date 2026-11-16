import Foundation
import Combine
import IOBluetooth

struct PairedAudioDevice: Identifiable, Equatable {
    let address: String
    let name: String
    let isBluetoothConnected: Bool

    var id: String { address }
}

struct BassEnhanceState: Equatable {
    let enabled: Bool
    let levelCount: Int
    private let savedWireLevel: UInt8?
    private var step: Int { levelCount == 2 ? 5 : 2 }
    var level: Int? { savedWireLevel.map { Int($0) / step } }

    init?(payload: [UInt8], previous: Self?, mayHaveTwoLevels: Bool) {
        guard payload.count >= 2, payload[0] <= 1 else { return nil }
        enabled = payload[0] == 1
        let wireLevel = Int(payload[1])
        switch wireLevel {
        case 5: levelCount = 2
        case 2, 4, 6, 8: levelCount = 5
        case 0, 10:
            levelCount = previous?.levelCount ?? (mayHaveTwoLevels ? 2 : 5)
        default: return nil
        }
        if wireLevel == 0 {
            guard !enabled else { return nil }
            savedWireLevel = previous?.savedWireLevel
        } else {
            savedWireLevel = payload[1]
        }
    }

    func payload(togglingTo enabled: Bool) -> [UInt8]? {
        guard self.enabled != enabled, let savedWireLevel else { return nil }
        return [enabled ? 1 : 0, !enabled && levelCount == 2 ? 0 : savedWireLevel]
    }

    func payload(selecting level: Int) -> [UInt8]? {
        guard (1...levelCount).contains(level), !enabled || self.level != level else { return nil }
        return [1, UInt8(level * step)]
    }
}

struct DualAudioPeer: Identifiable, Equatable {
    let address: [UInt8]
    let name: String
    let isThisMac: Bool
    let isConnected: Bool

    var id: [UInt8] { address }

    static func decodePage(_ payload: [UInt8]) -> [Self]? {
        guard payload.count >= 3 else { return nil }
        var peers: [Self] = []
        var offset = 3
        for _ in 0..<payload[2] {
            guard offset + 8 <= payload.count else { return nil }
            let flags = payload[offset]
            let nameStart = offset + 8
            let nameEnd = nameStart + Int(payload[offset + 7] & 0x7F)
            guard nameEnd <= payload.count else { return nil }
            let discoveredName = String(decoding: payload[nameStart..<nameEnd], as: UTF8.self)
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.controlCharacters))
            peers.append(Self(
                address: Array(payload[(offset + 1)..<(offset + 7)]),
                name: discoveredName.isEmpty ? "Bluetooth device" : discoveredName,
                isThisMac: flags & 0xF0 != 0,
                isConnected: flags & 0x0F != 0
            ))
            offset = nameEnd
        }
        return peers
    }
}

struct BasicAudioEQ: Equatable {
    enum Band: UInt8, CaseIterable {
        case bass, mid, treble

        var title: String {
            switch self {
            case .bass: return "Bass"
            case .mid: return "Mid"
            case .treble: return "Treble"
            }
        }
    }

    private(set) var gains: [Band: Double] = [:]
    private let original: [UInt8]
    private var gainOffsets: [Band: Int] = [:]

    init?(payload: [UInt8]) {
        guard payload.count >= 44, payload.first == 3 else { return nil }
        original = payload
        for index in 0..<3 {
            let offset = 5 + index * 13
            guard let band = Band(rawValue: payload[offset]), gains[band] == nil else { return nil }
            let bits = (0..<4).reduce(UInt32(0)) { $0 | (UInt32(payload[offset + 1 + $1]) << (8 * $1)) }
            let gain = Float(bitPattern: bits)
            guard gain.isFinite, (-6...6).contains(gain) else { return nil }
            gains[band] = Double(gain)
            gainOffsets[band] = offset + 1
        }
    }

    func payload(with gains: [Band: Double]) -> [UInt8]? {
        var result = original
        var peak: Float = 0
        func store(_ value: Float, at offset: Int) {
            for byte in 0..<4 { result[offset + byte] = UInt8(truncatingIfNeeded: value.bitPattern >> (byte * 8)) }
        }
        for band in Band.allCases {
            guard let gain = gains[band], gain.isFinite, (-6...6).contains(gain),
                  let offset = gainOffsets[band] else { return nil }
            peak = max(peak, Float(gain))
            store(Float(gain), at: offset)
        }
        store(-peak, at: 1)
        return result
    }
}

struct EarbudGesture: Identifiable, Equatable {
    struct ID: Hashable {
        let side: UInt8
        let button: UInt8
        let type: UInt8
    }

    let id: ID
    let action: UInt8

    static func decode(_ payload: [UInt8]) -> [Self]? {
        guard let count = payload.first, payload.count >= 1 + Int(count) * 4 else { return nil }
        return (0..<Int(count)).map { index in
            let offset = 1 + index * 4
            return Self(id: ID(side: payload[offset], button: payload[offset + 1], type: payload[offset + 2]),
                        action: payload[offset + 3])
        }
    }
}

/// Direct RFCOMM client for the shared Nothing / CMF earbud control service.
/// The packet layout and command IDs follow publicly documented community
/// implementations (ear-web and Nothing X Mac); this is independent code.
final class BluetoothManager: NSObject, ObservableObject, IOBluetoothRFCOMMChannelDelegate {
    static let shared = BluetoothManager()
    private static let artworkPreferencesKey = "pairedAudioArtworkVariants"

    @Published private(set) var connectionStatus = "Looking for paired Nothing and CMF audio devices…"
    @Published private(set) var deviceName = "Nothing X"
    @Published private(set) var isConnected = false
    @Published private(set) var pairedAudioDevices: [PairedAudioDevice] = []
    @Published private(set) var selectedPairedAddress: String?
    @Published private var artworkVariants: [String: String] =
        (UserDefaults.standard.dictionary(forKey: artworkPreferencesKey) as? [String: String]) ?? [:]
    @Published private(set) var leftBattery: Int?
    @Published private(set) var rightBattery: Int?
    @Published private(set) var caseBattery: Int?
    @Published private(set) var stereoBattery: Int?
    @Published private(set) var hasReportedNoiseControl = false
    @Published private(set) var noiseMode = "off"
    @Published private(set) var ancStrength = "high"
    @Published private(set) var equalizerPreset: Int?
    @Published private(set) var lowLatency = false
    @Published private(set) var inEarDetection = false
    @Published private(set) var hasReportedLowLatency = false
    @Published private(set) var hasReportedInEarDetection = false
    @Published private(set) var ringingSide: EarBudSide?
    @Published private(set) var bassEnhance: BassEnhanceState?
    @Published private(set) var personalSoundEnabled: Bool?
    @Published private(set) var dualConnectionEnabled: Bool?
    @Published private(set) var dualPeers: [DualAudioPeer] = []
    @Published private(set) var firmwareVersion: String?
    @Published private(set) var changingDualPeer = false
    @Published private(set) var basicEQ: BasicAudioEQ?
    @Published private(set) var advancedEQEnabled: Bool?
    @Published private(set) var gestures: [EarbudGesture] = []

    private var dualPagesRequested = 0
    @Published private(set) var dualListInProgress = false
    private var dualListGeneration = 0
    private var dualPeerRefresh: DispatchWorkItem?
    private var personalSoundBackend: PersonalSoundBackend?
    private var reportedEQ: AudioRead?

    // A connection may only request these values. Setting writes have separate call sites.
    private enum AudioRead: UInt16 {
        case deviceInfo = 0xC006
        case battery = 0xC007
        case noise = 0xC01E
        case eq = 0xC01F
        case listeningMode = 0xC050
        case lowLatency = 0xC041
        case inEar = 0xC00E
        case firmware = 0xC042
        case bass = 0xC04E
        case dualConnection = 0xC027
        case dualPeers = 0xC028
        case mimi = 0xC022
        case audiodo = 0xC05A
        case customEQ = 0xC044
        case advancedEQ = 0xC04C
        case gestures = 0xC018
    }

    private enum PersonalSoundBackend {
        case mimi, audiodo

        var read: AudioRead { self == .mimi ? .mimi : .audiodo }
        var write: UInt16 { self == .mimi ? 0xF015 : 0xF05C }
    }

    var audioModel: NearbyAudioModel? {
        selectedArtworkVariant?.model ?? AudioCatalog.shared.model(named: deviceName)
    }

    private var audioProfiles: [AudioProfile] {
        audioModel?.configurations(board: selectedArtworkVariant?.board, firmware: firmwareVersion) ?? []
    }

    var supportsBassEnhance: Bool { audioProfiles.contains(where: \.bass) || bassEnhance != nil }
    var supportsPersonalSound: Bool { audioProfiles.contains { $0.mimi || $0.audiodo } || personalSoundEnabled != nil }
    var supportsDualConnection: Bool { audioProfiles.contains(where: \.dual) || dualConnectionEnabled != nil }
    var supportsBasicEQ: Bool { audioProfiles.contains(where: \.customEQ) }
    var supportsLowLatency: Bool { audioProfiles.contains(where: \.lowLatency) }
    var supportsInEarDetection: Bool { audioProfiles.contains(where: \.inEar) }
    var supportsGestureControls: Bool { audioProfiles.contains { !$0.gestures.isEmpty } }
    var supportsEqualizer: Bool { audioModel.map { $0.kind != .speaker } == true || reportedEQ != nil }

    var equalizerProfile: NearbyAudioModel.EQ {
        guard let eq = audioModel?.eq, eq != .probe else {
            return reportedEQ == .listeningMode ? .listening : .equalizer
        }
        return eq
    }

    var canEditBasicEQ: Bool {
        isConnected && supportsBasicEQ && basicEQ != nil && reportedEQ != nil
            && (!audioProfiles.contains(where: \.advancedEQ) || advancedEQEnabled == false)
    }

    var availableNoiseModes: [String] {
        let flags = audioProfiles.reduce(0) { $0 | $1.anc }
        guard flags != 0 else { return [] }
        return flags & 0x10 != 0 ? ["anc", "transparency", "off"] : ["anc", "off"]
    }

    var availableANCStrengths: [String] {
        let flags = audioProfiles.reduce(0) { $0 | $1.anc }
        guard flags != 0 else { return [] }
        var strengths: [String] = []
        if flags & 0x04 != 0 { strengths.append("low") }
        if flags & 0x02 != 0 { strengths.append("mid") }
        strengths.append("high")
        if flags & 0x08 != 0 { strengths.append("adaptive") }
        return strengths
    }

    var gestureSides: [UInt8] {
        let sides = Set(audioProfiles.flatMap(\.gestures).map(\.side))
        return [2, 3, 4, 6, 7].filter { sides.contains($0) || ($0 == 3 && sides.contains(2)) }
    }

    func gestureSlot(for gesture: EarbudGesture) -> AudioGestureSlot? {
        audioProfiles.lazy.flatMap(\.gestures).first { $0.matches(gesture.id) }
    }

    private var ringStyle: AudioProfile.Ring { audioProfiles.first?.ring ?? .none }
    var supportsFindDevice: Bool { ringStyle != .none }
    var canRingIndividualBuds: Bool { ringStyle == .sides }
    var findDeviceTitle: String { audioModel?.kind == .earbuds ? "Find my earbuds" : "Find my device" }

    var selectedDeviceIsBluetoothConnected: Bool {
        pairedAudioDevices.contains { $0.address == selectedPairedAddress && $0.isBluetoothConnected }
    }

    var selectedArtworkVariant: NearbyAudioVariant? {
        artworkVariant(for: selectedPairedAddress)
    }

    func artworkVariant(for address: String?) -> NearbyAudioVariant? {
        guard let address, let value = artworkVariants[address.lowercased()] else { return nil }
        return NearbyAudioVariant(rawValue: value)
    }

    func setArtworkVariant(_ variant: NearbyAudioVariant?, for address: String) {
        let previous = artworkVariant(for: address)
        if let variant, variant.board == nil, let previous, previous.modelID == variant.modelID,
           let board = previous.board, variant.advertisements.values.contains(board) {
            artworkVariants[address.lowercased()] = "\(variant.id)/\(board)"
        } else {
            artworkVariants[address.lowercased()] = variant?.rawValue
        }
        UserDefaults.standard.set(artworkVariants, forKey: Self.artworkPreferencesKey)
    }

    func rememberArtworkVariant(_ variant: NearbyAudioVariant, for address: String) {
        if artworkVariant(for: address) == nil {
            setArtworkVariant(variant, for: address)
        }
    }

    func rememberArtworkAfterBluetoothSettings(_ variant: NearbyAudioVariant) {
        pendingArtwork = PendingArtwork(
            variant: variant,
            previouslyPaired: Set(recognizedPairedDevices().compactMap { $0.addressString?.lowercased() }),
            expiresAt: Date().addingTimeInterval(120)
        )
    }

    private struct PendingArtwork {
        let variant: NearbyAudioVariant
        let previouslyPaired: Set<String>
        let expiresAt: Date
    }

    private var pendingArtwork: PendingArtwork?

    private let serviceUUIDBytes: [UInt8] = [
        0xAE, 0xAC, 0x4A, 0x03, 0xDF, 0xF5, 0x49, 0x8F,
        0x84, 0x3A, 0x34, 0x48, 0x7C, 0xF1, 0x33, 0xEB
    ]
    private var serviceUUID: IOBluetoothSDPUUID!
    private var channel: IOBluetoothRFCOMMChannel?
    private var activeDevice: IOBluetoothDevice?
    private var sdpRequests: [String: Date] = [:]
    private var connectionAttemptAddress: String?
    private var inputBuffer = [UInt8]()
    private var scanTimer: Timer?
    private var batteryTimer: Timer?
    private var ringTimer: Timer?

    private override init() {
        super.init()
        serviceUUID = IOBluetoothSDPUUID(bytes: serviceUUIDBytes, length: 16)
        scanTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            self?.scanConnectedDevices()
        }
        scanConnectedDevices()
    }

    func reconnect() {
        let devices = recognizedPairedDevices()
        guard let target = devices.first(where: { $0.addressString == selectedPairedAddress })
            ?? devices.first(where: { $0.isConnected() })
            ?? devices.first else {
            pairedAudioDevices = []
            connectionStatus = "No paired Nothing or CMF audio devices found"
            return
        }
        reconnect(to: target.addressString ?? "")
    }

    func refreshPairedDevices() {
        scanConnectedDevices()
    }

    func reconnect(to address: String) {
        let devices = recognizedPairedDevices()
        guard let candidate = devices.first(where: { $0.addressString == address }) else {
            connectionStatus = "Paired device is no longer available. Refresh and try again."
            return
        }

        let targetAddress = candidate.addressString ?? address
        let targetName = candidate.name ?? candidate.nameOrAddress ?? "Nothing / CMF audio device"
        if let activeDevice, activeDevice.addressString != targetAddress {
            closeControlChannel()
        }
        selectedPairedAddress = targetAddress
        deviceName = targetName
        guard !isConnected, connectionAttemptAddress == nil else { return }
        connectionStatus = candidate.isConnected() ? "Looking for the device control service…" : "Connecting to \(targetName)…"

        if candidate.isConnected() {
            candidate.performSDPQuery(nil)
            scanConnectedDevices()
            return
        }

        connectionAttemptAddress = targetAddress
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = candidate.openConnection()
            DispatchQueue.main.async {
                guard let self else { return }
                self.connectionAttemptAddress = nil
                guard result == kIOReturnSuccess || candidate.isConnected() else {
                    self.connectionStatus = "Couldn’t connect. Check Bluetooth Settings and try again."
                    return
                }
                self.connectionStatus = "Looking for the device control service…"
                candidate.performSDPQuery(nil)
                self.scanConnectedDevices()
            }
        }
    }

    func disconnect() {
        closeControlChannel()
        connectionStatus = "Disconnected"
    }

    private func closeControlChannel() {
        batteryTimer?.invalidate()
        batteryTimer = nil
        if let ringingSide { ring(side: ringingSide, enabled: false) }
        if let channel {
            self.channel = nil
            channel.setDelegate(nil)
            channel.close()
        }
        activeDevice = nil
        isConnected = false
        ringingSide = nil
        resetAudioFeatures()
    }

    func setNoiseControl(_ mode: String, strength: String = "high") {
        guard isConnected, hasReportedNoiseControl, availableNoiseModes.contains(mode) else { return }
        let strength = availableANCStrengths.contains(strength) ? strength : "high"
        guard mode != noiseMode || (mode == "anc" && strength != ancStrength) else { return }
        let code: UInt8
        switch mode {
        case "anc":
            switch strength {
            case "low": code = 0x03
            case "mid": code = 0x02
            case "adaptive": code = 0x04
            default: code = 0x01
            }
        case "transparency": code = 0x07
        default: code = 0x05
        }
        send(command: 0xF00F, payload: [0x01, code, 0x00])
        readAfterWrite(.noise)
    }

    func setEqualizerPreset(_ preset: Int) {
        guard isConnected, let reportedEQ, let equalizerPreset, preset != equalizerPreset,
              let wirePreset = UInt8(exactly: preset) else { return }
        send(command: reportedEQ == .listeningMode ? 0xF01D : 0xF010, payload: [wirePreset, 0x00])
        readAfterWrite(reportedEQ)
    }

    func setLowLatency(_ enabled: Bool) {
        guard isConnected, supportsLowLatency, hasReportedLowLatency, enabled != lowLatency else { return }
        send(command: 0xF040, payload: [enabled ? 0x01 : 0x02, 0x00])
        readAfterWrite(.lowLatency)
    }

    func setInEarDetection(_ enabled: Bool) {
        guard isConnected, supportsInEarDetection, hasReportedInEarDetection, enabled != inEarDetection else { return }
        send(command: 0xF004, payload: [0x01, 0x01, enabled ? 0x01 : 0x00])
        readAfterWrite(.inEar)
    }

    func setBassEnhanceEnabled(_ enabled: Bool) {
        guard isConnected, let payload = bassEnhance?.payload(togglingTo: enabled) else { return }
        send(command: 0xF051, payload: payload)
        readAfterWrite(.bass)
    }

    func selectBassEnhanceLevel(_ level: Int) {
        guard isConnected, let payload = bassEnhance?.payload(selecting: level) else { return }
        send(command: 0xF051, payload: payload)
        readAfterWrite(.bass)
    }

    func setPersonalSound(_ enabled: Bool) {
        guard isConnected, let personalSoundBackend, personalSoundEnabled != enabled else { return }
        send(command: personalSoundBackend.write, payload: [enabled ? 1 : 0])
        readAfterWrite(personalSoundBackend.read)
    }

    func setDualConnection(_ enabled: Bool) {
        guard isConnected, let dualConnectionEnabled, dualConnectionEnabled != enabled else { return }
        send(command: 0xF01A, payload: [enabled ? 1 : 0])
        readAfterWrite(.dualConnection)
    }

    func refreshDualPeers() {
        guard isConnected, dualConnectionEnabled == true, !dualListInProgress else { return }
        dualPagesRequested = 1
        dualPeers = []
        dualListInProgress = true
        dualListGeneration += 1
        let generation = dualListGeneration
        read(.dualPeers, payload: [0])
        withCurrentChannel(after: 4) {
            if $0.dualListGeneration == generation { $0.dualListInProgress = false }
        }
    }

    func setDualPeerConnection(_ peer: DualAudioPeer, connected: Bool) {
        guard isConnected, dualConnectionEnabled == true, !changingDualPeer,
              let current = dualPeers.first(where: { $0.id == peer.id }), !current.isThisMac,
              current.isConnected != connected,
              !connected || dualPeers.filter(\.isConnected).count < 2 else { return }
        send(command: 0xF01B, payload: [connected ? 1 : 0] + current.address)
        changingDualPeer = true
        dualPeerRefresh?.cancel()
        let refresh = DispatchWorkItem { [weak self] in
            self?.changingDualPeer = false
            self?.refreshDualPeers()
        }
        dualPeerRefresh = refresh
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: refresh)
    }

    private func withCurrentChannel(after delay: TimeInterval, action: @escaping (BluetoothManager) -> Void) {
        guard let channel else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak channel] in
            guard let self, let channel, self.channel === channel else { return }
            action(self)
        }
    }

    private func read(_ command: AudioRead, payload: [UInt8] = []) {
        send(command: command.rawValue, payload: payload)
    }

    private func readAfterWrite(_ command: AudioRead) {
        withCurrentChannel(after: 0.3) { $0.read(command) }
    }

    private func resetAudioFeatures() {
        leftBattery = nil
        rightBattery = nil
        caseBattery = nil
        stereoBattery = nil
        hasReportedNoiseControl = false
        hasReportedLowLatency = false
        hasReportedInEarDetection = false
        noiseMode = "off"
        ancStrength = "high"
        lowLatency = false
        inEarDetection = false
        equalizerPreset = nil
        reportedEQ = nil
        bassEnhance = nil
        personalSoundEnabled = nil
        personalSoundBackend = nil
        dualConnectionEnabled = nil
        dualPeers = []
        dualListInProgress = false
        changingDualPeer = false
        dualPeerRefresh?.cancel()
        dualPeerRefresh = nil
        firmwareVersion = nil
        basicEQ = nil
        advancedEQEnabled = nil
        gestures = []
    }

    func applyBasicEQ(_ gains: [BasicAudioEQ.Band: Double]) {
        guard canEditBasicEQ, let reportedEQ, let payload = basicEQ?.payload(with: gains) else { return }
        let isCMF = reportedEQ == .listeningMode
        send(command: isCMF ? 0xF01D : 0xF010, payload: [isCMF ? 6 : 5, 0])
        withCurrentChannel(after: 0.18) { manager in
            manager.send(command: 0xF041, payload: payload)
            manager.readAfterWrite(.customEQ)
            manager.readAfterWrite(reportedEQ)
        }
    }

    func setGesture(_ gesture: EarbudGesture, action: UInt8) {
        guard isConnected, gestureSlot(for: gesture)?.actions.contains(action) == true,
              let current = gestures.first(where: { $0.id == gesture.id }), current.action != action else { return }
        let id = gesture.id
        send(command: 0xF003, payload: [1, id.side, id.button, id.type, action])
        readAfterWrite(.gestures)
    }

    private func ring(side: EarBudSide, enabled: Bool) {
        guard isConnected else { return }
        let flag: UInt8 = enabled ? 1 : 0
        let payload: [UInt8]
        switch ringStyle {
        case .none: return
        case .legacy: payload = [flag]
        case .single: payload = [0x06, flag]
        case .sides: payload = [side == .right ? 0x03 : 0x02, flag]
        }
        ringTimer?.invalidate()
        ringTimer = nil
        send(command: 0xF002, payload: payload)
        ringingSide = enabled ? side : nil
        if enabled {
            ringTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in
                self?.ring(side: side, enabled: false)
            }
        }
    }

    func toggleRing(side: EarBudSide) {
        if let ringingSide {
            ring(side: ringingSide, enabled: false)
            if ringingSide == side { return }
        }
        ring(side: side, enabled: true)
    }

    private func scanConnectedDevices() {
        let paired = recognizedPairedDevices()
        resolvePendingArtwork(in: paired)
        let summaries = paired.map {
            PairedAudioDevice(
                address: $0.addressString ?? $0.nameOrAddress ?? UUID().uuidString,
                name: $0.name ?? $0.nameOrAddress ?? "Nothing / CMF audio device",
                isBluetoothConnected: $0.isConnected()
            )
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        DispatchQueue.main.async {
            self.pairedAudioDevices = summaries
            if let preferred = paired.first(where: { $0.addressString == self.selectedPairedAddress })
                ?? paired.first(where: { $0.isConnected() })
                ?? paired.first {
                self.selectedPairedAddress = preferred.addressString
                self.deviceName = preferred.name ?? preferred.nameOrAddress ?? "Nothing / CMF audio device"
            } else {
                self.selectedPairedAddress = nil
                self.deviceName = "Nothing X"
            }
            if !self.isConnected && self.connectionAttemptAddress == nil {
                if summaries.isEmpty {
                    self.connectionStatus = "No paired Nothing or CMF audio devices found"
                } else if let selected = paired.first(where: { $0.addressString == self.selectedPairedAddress }),
                          selected.isConnected() {
                    self.connectionStatus = self.sdpRequests[selected.addressString ?? ""] != nil
                        ? "Bluetooth connected · device controls unavailable"
                        : "Bluetooth connected · looking for device controls…"
                } else {
                    self.connectionStatus = "Paired device found · connect to enable controls"
                }
            }
        }

        guard channel == nil, connectionAttemptAddress == nil else { return }

        let scanOrder: [IOBluetoothDevice]
        if let selectedPairedAddress,
           let selected = paired.first(where: { $0.addressString == selectedPairedAddress }) {
            scanOrder = [selected]
        } else {
            scanOrder = paired
        }

        for candidate in scanOrder where candidate.isConnected() {
            let address = candidate.addressString ?? candidate.nameOrAddress ?? "unknown"
            guard let service = candidate.getServiceRecord(for: serviceUUID) else {
                if Date().timeIntervalSince(sdpRequests[address] ?? .distantPast) > 8 {
                    sdpRequests[address] = Date()
                    candidate.performSDPQuery(nil)
                }
                continue
            }

            var channelID: BluetoothRFCOMMChannelID = 0
            guard service.getRFCOMMChannelID(&channelID) == kIOReturnSuccess else { continue }
            var opened: IOBluetoothRFCOMMChannel?
            let result = candidate.openRFCOMMChannelSync(&opened, withChannelID: channelID, delegate: self)
            guard result == kIOReturnSuccess, let opened else { continue }

            channel = opened
            activeDevice = candidate
            sdpRequests.removeValue(forKey: address)
            inputBuffer.removeAll(keepingCapacity: true)
            let name = candidate.name ?? candidate.nameOrAddress ?? "Nothing / CMF audio device"
            DispatchQueue.main.async {
                self.deviceName = name
                self.selectedPairedAddress = candidate.addressString
                self.isConnected = true
                self.connectionStatus = "Connected"
            }
            requestInitialState(for: candidate)
            batteryTimer = Timer.scheduledTimer(withTimeInterval: 25, repeats: true) { [weak self] _ in
                self?.read(.battery)
            }
            return
        }
    }

    private func resolvePendingArtwork(in paired: [IOBluetoothDevice]) {
        guard let pendingArtwork else { return }
        guard Date() < pendingArtwork.expiresAt else {
            self.pendingArtwork = nil
            return
        }
        let model = pendingArtwork.variant.model
        let newAddresses = Set(paired.filter(model.matches).compactMap { $0.addressString?.lowercased() })
            .subtracting(pendingArtwork.previouslyPaired)
        guard !newAddresses.isEmpty else { return }
        self.pendingArtwork = nil
        if newAddresses.count == 1, let address = newAddresses.first {
            rememberArtworkVariant(pendingArtwork.variant, for: address)
        }
    }

    private func recognizedPairedDevices() -> [IOBluetoothDevice] {
        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return [] }
        return paired.filter { device in
            AudioCatalog.shared.model(named: device.name ?? device.nameOrAddress ?? "") != nil
                || artworkVariant(for: device.addressString) != nil
        }
    }

    private func requestInitialState(for device: IOBluetoothDevice) {
        let variant = artworkVariant(for: device.addressString)
        guard let model = variant?.model ?? AudioCatalog.shared.model(named: device.name ?? device.nameOrAddress ?? "") else { return }
        let profiles = model.configurations(board: variant?.board, firmware: nil)
        var reads: [AudioRead] = [.battery, .firmware]
        if profiles.contains(where: { $0.anc != 0 }) { reads.append(.noise) }
        if model.eq == .probe {
            reads += [.eq, .listeningMode]
        } else {
            reads.append(model.eq.usesListeningMode ? .listeningMode : .eq)
        }
        if profiles.contains(where: \.lowLatency) { reads.append(.lowLatency) }
        if profiles.contains(where: \.inEar) { reads.append(.inEar) }
        if profiles.contains(where: \.bass) { reads.append(.bass) }
        if profiles.contains(where: \.dual) { reads.append(.dualConnection) }
        if profiles.contains(where: \.mimi) { reads.append(.mimi) }
        if profiles.contains(where: \.audiodo) { reads.append(.audiodo) }
        if profiles.contains(where: \.customEQ) { reads.append(.customEQ) }
        if profiles.contains(where: \.advancedEQ) { reads.append(.advancedEQ) }
        if profiles.contains(where: { !$0.gestures.isEmpty }) { reads.append(.gestures) }
        // Some firmware ignores state queries until the read-only device info request.
        withCurrentChannel(after: 0) { $0.read(.deviceInfo) }
        for (index, command) in reads.enumerated() {
            withCurrentChannel(after: 0.5 + Double(index) * 0.16) { $0.read(command) }
        }
    }

    private func send(command: UInt16, payload: [UInt8] = [], operationID: UInt8 = 0) {
        guard let channel else { return }
        var frame: [UInt8] = [0x55, 0x60, 0x01,
                              UInt8(command & 0xFF), UInt8(command >> 8),
                              UInt8(clamping: payload.count), 0, operationID]
        frame.append(contentsOf: payload)
        let crc = Self.crc16Modbus(frame)
        frame.append(UInt8(crc & 0xFF))
        frame.append(UInt8(crc >> 8))
        let result = frame.withUnsafeMutableBytes { bytes in
            channel.writeSync(bytes.baseAddress, length: UInt16(bytes.count))
        }
        if result != kIOReturnSuccess {
            DispatchQueue.main.async { self.connectionStatus = "Bluetooth write failed (\(result))" }
        }
    }

    private static func crc16Modbus(_ bytes: [UInt8]) -> UInt16 {
        var crc: UInt16 = 0xFFFF
        for byte in bytes {
            crc ^= UInt16(byte)
            for _ in 0..<8 {
                crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xA001 : crc >> 1
            }
        }
        return crc
    }

    private func consume(_ newBytes: [UInt8]) {
        inputBuffer.append(contentsOf: newBytes)
        while let start = inputBuffer.firstIndex(of: 0x55) {
            if start > 0 { inputBuffer.removeFirst(start) }
            guard inputBuffer.count >= 8 else { return }
            let bodyLength = 8 + Int(inputBuffer[5]) + (Int(inputBuffer[6]) << 8)
            let hasCRC = inputBuffer[1] & 0x20 != 0
            let frameLength = bodyLength + (hasCRC ? 2 : 0)
            guard frameLength <= 4096 else {
                inputBuffer.removeFirst()
                continue
            }
            guard inputBuffer.count >= frameLength else { return }

            let body = Array(inputBuffer.prefix(bodyLength))
            if hasCRC {
                let actual = UInt16(inputBuffer[bodyLength]) | (UInt16(inputBuffer[bodyLength + 1]) << 8)
                guard Self.crc16Modbus(body) == actual else {
                    inputBuffer.removeFirst()
                    continue
                }
            }
            let payload = Array(body.dropFirst(8))
            let command = UInt16(body[3]) | (UInt16(body[4]) << 8)
            handle(command: command, payload: payload)
            inputBuffer.removeFirst(frameLength)
        }
        inputBuffer.removeAll(keepingCapacity: true)
    }

    private func handle(command: UInt16, payload: [UInt8]) {
        guard let channel else { return }
        DispatchQueue.main.async { [weak self, weak channel] in
            guard let self, let channel, self.channel === channel else { return }
            self.handleCurrentFrame(command: command, payload: payload)
        }
    }

    private func handleCurrentFrame(command: UInt16, payload: [UInt8]) {
        switch command {
        case 0x4007, 0xE001:
            guard let count = payload.first else { return }
            var levels: [UInt8: Int] = [:]
            for i in 0..<Int(count) {
                let index = 1 + i * 2
                guard payload.count > index + 1 else { break }
                let level = Int(payload[index + 1] & 0x7F)
                if level <= 100 { levels[payload[index]] = level }
            }
            leftBattery = levels[0x02]
            rightBattery = levels[0x03]
            caseBattery = levels[0x04]
            stereoBattery = levels[0x06]
        case 0x401E, 0xE003, 0x6003:
            guard payload.count >= 3, payload[0] == 1 else { return }
            let strengths: [UInt8: String] = [1: "high", 2: "mid", 3: "low", 4: "adaptive"]
            if let strength = strengths[payload[1]] {
                noiseMode = "anc"
                ancStrength = strength
            } else {
                switch payload[1] {
                case 5: noiseMode = "off"
                case 7: noiseMode = "transparency"
                default: return
                }
            }
            if payload.count >= 6, payload[3] == 2, let strength = strengths[payload[4]] {
                ancStrength = strength
            }
            hasReportedNoiseControl = true
        case 0x401F, 0x4050:
            let read: AudioRead = command == 0x4050 ? .listeningMode : .eq
            let profile = audioModel?.eq
            guard let value = payload.first, value <= 7,
                  profile == .probe || (profile?.usesListeningMode == true) == (read == .listeningMode),
                  reportedEQ == nil || reportedEQ == read else { return }
            reportedEQ = read
            equalizerPreset = Int(value)
        case 0x4041:
            if let value = payload.first, value <= 2 {
                lowLatency = value == 1
                hasReportedLowLatency = true
            }
        case 0x400E:
            if payload.count > 2, payload[2] <= 1 {
                inEarDetection = payload[2] == 1
                hasReportedInEarDetection = true
            }
        default:
            handleAudioFeatures(command: command, payload: payload)
        }
    }

    private func handleAudioFeatures(command: UInt16, payload: [UInt8]) {
        switch command {
        case 0x404E:
            if let state = BassEnhanceState(payload: payload, previous: bassEnhance,
                                           mayHaveTwoLevels: audioProfiles.contains(where: \.twoBass)) {
                bassEnhance = state
            }
        case 0x4022, 0x405A, 0xE019, 0x6019:
            let backend: PersonalSoundBackend = command == 0x4022 ? .mimi : .audiodo
            guard audioProfiles.contains(where: { backend == .mimi ? $0.mimi : $0.audiodo }), let value = payload.first, value <= 1,
                  personalSoundBackend == nil || personalSoundBackend == backend else { return }
            personalSoundBackend = backend
            personalSoundEnabled = value == 1
        case 0x4027:
            guard let value = payload.first, value <= 1 else { return }
            let wasOn = dualConnectionEnabled == true
            dualConnectionEnabled = value == 1
            if value == 1 && !wasOn { refreshDualPeers() }
            if value == 0 {
                dualPeers = []
                dualListInProgress = false
            }
        case 0x4028:
            guard dualListInProgress else { return }
            guard let page = DualAudioPeer.decodePage(payload) else {
                dualListInProgress = false
                return
            }
            let countBefore = dualPeers.count
            for peer in page {
                if let index = dualPeers.firstIndex(where: { $0.id == peer.id }) {
                    dualPeers[index] = peer
                } else {
                    dualPeers.append(peer)
                }
            }
            if dualPeers.count > countBefore, dualPagesRequested < 20, dualPeers.count <= 255 {
                dualPagesRequested += 1
                read(.dualPeers, payload: [UInt8(dualPeers.count)])
            } else {
                dualListInProgress = false
            }
        case 0xE00E:
            dualPeerRefresh?.cancel()
            changingDualPeer = false
            refreshDualPeers()
        case 0x4042:
            if let version = String(bytes: payload.prefix(while: { $0 != 0 }), encoding: .ascii)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !version.isEmpty {
                firmwareVersion = version
            }
        case 0x4044:
            basicEQ = BasicAudioEQ(payload: payload)
        case 0x404C:
            if let value = payload.first, value <= 1 { advancedEQEnabled = value == 1 }
        case 0x4018:
            if let records = EarbudGesture.decode(payload) { gestures = records }
        default:
            break
        }
    }

    // MARK: IOBluetoothRFCOMMChannelDelegate

    func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!,
                          data dataPointer: UnsafeMutableRawPointer!,
                          length dataLength: Int) {
        guard rfcommChannel === channel, dataLength > 0, let dataPointer else { return }
        let bytes = Array(UnsafeBufferPointer(start: dataPointer.assumingMemoryBound(to: UInt8.self), count: dataLength))
        consume(bytes)
    }

    func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        guard rfcommChannel === channel else { return }
        channel = nil
        activeDevice = nil
        batteryTimer?.invalidate()
        batteryTimer = nil
        ringTimer?.invalidate()
        ringTimer = nil
        DispatchQueue.main.async {
            guard self.channel == nil else { return }
            self.isConnected = false
            self.ringingSide = nil
            self.resetAudioFeatures()
            self.connectionStatus = "Device disconnected. Waiting to reconnect…"
        }
    }
}

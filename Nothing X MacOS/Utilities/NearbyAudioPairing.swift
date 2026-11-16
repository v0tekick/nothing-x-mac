import Combine
import CoreBluetooth
import IOBluetooth

final class NearbyAudioPairing: NSObject, ObservableObject, CBCentralManagerDelegate,
    IOBluetoothDeviceInquiryDelegate, IOBluetoothDevicePairDelegate {
    static let preferenceKey = "nearbyPairingPrompts"

    struct Candidate {
        let variant: NearbyAudioVariant
        let device: IOBluetoothDevice?
    }

    enum Phase: Equatable {
        case ready
        case pairing
        case paired
        case needsSettings
    }

    @Published private(set) var phase = Phase.ready
    var onCandidate: ((Candidate) -> Void)?
    var canOfferPrompt: (() -> Bool)?

    private let fastPairService = CBUUID(string: "FE2C")
    private var central: CBCentralManager?
    private var preferencesObserver: NSObjectProtocol?
    private var inquiry: IOBluetoothDeviceInquiry?
    private var searchingFor: NearbyAudioVariant?
    private var lastDiscovery = [NearbyAudioVariant: Date]()
    private var pair: IOBluetoothDevicePair?
    private var timeout: Timer?

    func start() {
        preferencesObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.updateScanning()
        }
        updateScanning()
    }

    func stop() {
        if let preferencesObserver { NotificationCenter.default.removeObserver(preferencesObserver) }
        preferencesObserver = nil
        central?.stopScan()
        cancelInquiry()
        cancelPairing()
    }

    private func updateScanning() {
        guard UserDefaults.standard.object(forKey: Self.preferenceKey) as? Bool ?? true else {
            central?.stopScan()
            cancelInquiry()
            return
        }
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main, options: [CBCentralManagerOptionShowPowerAlertKey: false])
        } else if central?.state == .poweredOn, central?.isScanning == false {
            // Fast Pair can advertise FE2C in Service Data without listing it as a service UUID.
            central?.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            updateScanning()
        } else {
            cancelInquiry()
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard inquiry == nil, pair == nil,
              (-65 ... -1).contains(RSSI.intValue),
              let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data],
              let payload = serviceData[fastPairService],
              let variant = NearbyAudioVariant.advertised(in: payload),
              canOfferPrompt?() == true,
              Date().timeIntervalSince(lastDiscovery[variant] ?? .distantPast) >= 120 else { return }

        lastDiscovery[variant] = Date()
        searchingFor = variant
        guard let inquiry = IOBluetoothDeviceInquiry(delegate: self) else {
            finishInquiry(with: [])
            return
        }
        inquiry.inquiryLength = 5
        inquiry.updateNewDeviceNames = true
        self.inquiry = inquiry
        if inquiry.start() != kIOReturnSuccess {
            finishInquiry(with: [])
        } else if self.inquiry === inquiry {
            timeout = Timer.scheduledTimer(withTimeInterval: 14, repeats: false) { [weak self] _ in
                self?.finishInquiry(with: [])
            }
        }
    }

    func deviceInquiryComplete(_ sender: IOBluetoothDeviceInquiry!, error: IOReturn, aborted: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self, sender === self.inquiry else { return }
            self.finishInquiry(with: error == kIOReturnSuccess && !aborted
                ? sender.foundDevices() as? [IOBluetoothDevice] ?? [] : [])
        }
    }

    private func finishInquiry(with devices: [IOBluetoothDevice]) {
        guard let variant = searchingFor else { return }
        cancelInquiry()
        let model = variant.model
        let matches = devices.filter { model.matches($0) && !$0.isPaired() && $0.addressString != nil }
        if matches.count == 1, let match = matches.first {
            onCandidate?(Candidate(variant: variant, device: match))
        } else {
            let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
            if !matches.isEmpty || !paired.contains(where: model.matches) {
                onCandidate?(Candidate(variant: variant, device: nil))
            }
        }
    }

    private func cancelInquiry() {
        searchingFor = nil
        guard let inquiry else { return }
        self.inquiry = nil
        clearTimeout()
        inquiry.delegate = nil
        inquiry.stop()
    }

    func preparePrompt(for candidate: Candidate) {
        phase = candidate.device == nil ? .needsSettings : .ready
    }

    func pairDevice(_ candidate: Candidate) {
        guard pair == nil, let device = candidate.device else { return }
        if let address = device.addressString {
            BluetoothManager.shared.rememberArtworkVariant(candidate.variant, for: address)
        }
        if device.isPaired() {
            finishPairing(device)
            return
        }

        cancelInquiry()
        guard let attempt = IOBluetoothDevicePair(device: device) else {
            phase = .needsSettings
            return
        }

        attempt.delegate = self
        pair = attempt
        phase = .pairing
        if attempt.start() != kIOReturnSuccess {
            useBluetoothSettings()
        } else if pair === attempt {
            timeout = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in
                self?.useBluetoothSettings()
            }
        }
    }

    func cancelPairing() {
        guard let pair else { return }
        self.pair = nil
        clearTimeout()
        pair.delegate = nil
        pair.stop()
    }

    private func useBluetoothSettings() {
        cancelPairing()
        phase = .needsSettings
    }

    func devicePairingFinished(_ sender: Any!, error: IOReturn) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let attempt = sender as? IOBluetoothDevicePair, attempt === self.pair else { return }
            self.pair = nil
            self.clearTimeout()
            attempt.delegate = nil
            if error == kIOReturnSuccess, let device = attempt.device() {
                self.finishPairing(device)
            } else {
                self.phase = .needsSettings
            }
        }
    }

    func devicePairingPINCodeRequest(_ sender: Any!) { handOffPairing(sender) }
    func devicePairingUserConfirmationRequest(_ sender: Any!, numericValue: BluetoothNumericValue) { handOffPairing(sender) }
    func devicePairingUserPasskeyNotification(_ sender: Any!, passkey: BluetoothPasskey) { handOffPairing(sender) }

    private func handOffPairing(_ sender: Any?) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let attempt = sender as? IOBluetoothDevicePair, attempt === self.pair else { return }
            self.useBluetoothSettings()
        }
    }

    private func finishPairing(_ device: IOBluetoothDevice) {
        phase = .paired
        BluetoothManager.shared.refreshPairedDevices()
        if let address = device.addressString {
            BluetoothManager.shared.reconnect(to: address)
        }
    }

    private func clearTimeout() {
        timeout?.invalidate()
        timeout = nil
    }
}

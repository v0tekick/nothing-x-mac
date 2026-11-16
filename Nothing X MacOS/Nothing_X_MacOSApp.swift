//
//  Nothing_X_MacOSApp.swift
//  Nothing X MacOS
//

import SwiftUI
import AppKit
import CoreServices
import IOBluetooth

@MainActor
final class NothingXAppDelegate: NSObject, NSApplicationDelegate {
    private let menuBar = NothingMenuBarController()
    private weak var mainWindow: NSWindow?
    private var openWindow: OpenWindowAction?
    private var quitRequestedFromMiniWindow = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBar.openMainWindow = { [weak self] in self?.showMainWindow() }
        menuBar.quitApp = { [weak self] in
            guard let self else { return }
            self.quitRequestedFromMiniWindow = true
            NSApp.terminate(nil)
        }
        menuBar.start()
    }

    func registerOpenWindowAction(_ action: OpenWindowAction) {
        openWindow = action
    }

    func registerMainWindow(_ window: NSWindow) {
        guard mainWindow !== window else { return }
        if let mainWindow {
            NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: mainWindow)
        }
        mainWindow = window
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarAppearsTransparent = true
        if let closeButton = window.standardWindowButton(.closeButton) {
            closeButton.target = self
            closeButton.action = #selector(hideMainWindow)
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(mainWindowWillClose),
            name: NSWindow.willCloseNotification, object: window
        )
    }

    @objc private func mainWindowWillClose(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: notification.object)
        mainWindow = nil
    }

    @objc private func hideMainWindow(_ sender: Any?) {
        mainWindow?.orderOut(sender)
        if NSApp.isActive { NSApp.deactivate() }
    }

    private func showMainWindow() {
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        if let mainWindow {
            mainWindow.makeKeyAndOrderFront(nil)
        } else if let openWindow {
            openWindow(id: "main")
        } else {
            NSWorkspace.shared.open(Bundle.main.bundleURL)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        guard !hasVisibleWindows, mainWindow != nil || openWindow != nil else { return true }
        showMainWindow()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if quitRequestedFromMiniWindow || isSystemQuitRequest {
            return .terminateNow
        }
        hideMainWindow(nil)
        return .terminateCancel
    }

    private var isSystemQuitRequest: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventClass == AEEventClass(kCoreEventClass),
              event.eventID == AEEventID(kAEQuitApplication),
              let reason = event.paramDescriptor(forKeyword: AEKeyword(kAEQuitReason))?.enumCodeValue else {
            return false
        }
        return [kAEQuitAll, kAEShutDown, kAERestart, kAEReallyLogOut].contains(reason)
    }

    func applicationWillTerminate(_ notification: Notification) {
        menuBar.stop()
        BluetoothManager.shared.disconnect()
    }
}

@main
struct Nothing_X_MacOSApp: App {
    @NSApplicationDelegateAdaptor(NothingXAppDelegate.self) private var appDelegate
    @StateObject private var store = Store()

    var body: some Scene {
        Window("Nothing X", id: "main") {
            MainNavigationView(
                registerMainWindow: appDelegate.registerMainWindow,
                registerOpenWindowAction: appDelegate.registerOpenWindowAction
            )
            .environmentObject(store)
        }
        .defaultSize(width: store.windowShape.size.width, height: store.windowShape.size.height)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appTermination) {}
        }
    }
}

private struct MainNavigationView: View {
    let registerMainWindow: (NSWindow) -> Void
    let registerOpenWindowAction: (OpenWindowAction) -> Void
    @Environment(\.openWindow) private var openWindow
    @StateObject private var windowController = MainWindowController()

    var body: some View {
        NavigationStack {
            HomeView()
                .navigationDestination(for: Destination.self) { destination in
                    switch destination {
                    case .home: HomeView()
                    case .devices: DevicesView()
                    case .equalizer: EqualizerView()
                    case .controls: ControlsView()
                    case .settings:
                        SettingsView(applyWindowPreset: windowController.resize)
                    case .bassEnhance: BassEnhanceView()
                    case .personalSound: PersonalSoundView()
                    case .dualConnection: DualConnectionView()
                    case .audioDeviceSettings: AudioDeviceSettingsView()
                    case .aboutDevice: AudioDeviceAboutView()
                    case .findMyBuds: FindMyBudsView()
                    }
                }
        }
        .frame(minWidth: 360, maxWidth: .infinity, minHeight: 240, maxHeight: .infinity)
        .background { NothingMainWindowBackground().ignoresSafeArea() }
        .background {
            MainWindowAccessor { window in
                windowController.window = window
                registerMainWindow(window)
            }
            .frame(width: 0, height: 0)
        }
        .preferredColorScheme(.dark)
        .onAppear { registerOpenWindowAction(openWindow) }
    }
}

@MainActor
private final class MainWindowController: ObservableObject {
    weak var window: NSWindow?

    func resize(to shape: PopupWindowShape) {
        window?.setContentSize(shape.size)
    }
}

private struct MainWindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void

    func makeNSView(context: Context) -> WindowObserver {
        let observer = WindowObserver()
        observer.onResolve = onResolve
        return observer
    }

    func updateNSView(_ observer: WindowObserver, context: Context) {
        observer.onResolve = onResolve
    }

    final class WindowObserver: NSView {
        var onResolve: ((NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { onResolve?(window) }
        }
    }
}

@MainActor
private final class NothingMenuBarController: NSObject, NSPopoverDelegate {
    var openMainWindow: (() -> Void)?
    var quitApp: (() -> Void)?

    private let popover = NSPopover()
    private let pairing = NearbyAudioPairing()
    private var statusItem: NSStatusItem?
    private var promptTimeout: Timer?

    func start() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item
        if let button = item.button {
            let image = NSImage(systemSymbolName: "earbuds", accessibilityDescription: nil)
            image?.isTemplate = true
            button.image = image
            button.setAccessibilityLabel("Nothing X")
            button.toolTip = "Nothing X"
            button.target = self
            button.action = #selector(toggleDashboard)
        }
        popover.behavior = .transient
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.delegate = self
        pairing.canOfferPrompt = { [weak self] in
            guard let self else { return false }
            return !self.popover.isShown && self.statusItem?.button?.window?.isVisible == true
        }
        pairing.onCandidate = { [weak self] candidate in self?.showPairing(candidate) }
        pairing.start()
    }

    func stop() {
        pairing.stop()
        promptTimeout?.invalidate()
        popover.performClose(nil)
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
    }

    @objc private func toggleDashboard() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        show(MenuBarNavigationView(
            openMainWindow: { [weak self] in
                self?.popover.performClose(nil)
                self?.openMainWindow?()
            },
            quitApp: { [weak self] in self?.quitApp?() }
        ), size: NSSize(width: 358, height: 330))
    }

    private func showPairing(_ candidate: NearbyAudioPairing.Candidate) {
        guard !popover.isShown else { return }
        pairing.preparePrompt(for: candidate)
        show(NearbyPairingPrompt(
            candidate: candidate,
            pairing: pairing,
            close: { [weak self] in self?.popover.performClose(nil) },
            pair: { [weak self] in
                self?.promptTimeout?.invalidate()
                self?.pairing.pairDevice(candidate)
            }
        ), size: NSSize(width: 308, height: 262))
        if popover.isShown {
            promptTimeout = Timer.scheduledTimer(withTimeInterval: 25, repeats: false) { [weak self] _ in
                DispatchQueue.main.async { self?.popover.performClose(nil) }
            }
        }
    }

    private func show<Content: View>(_ view: Content, size: NSSize) {
        guard let button = statusItem?.button, let window = button.window, window.isVisible else { return }
        popover.contentViewController = NSHostingController(rootView: view)
        popover.contentSize = size
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    func popoverWillClose(_ notification: Notification) {
        promptTimeout?.invalidate()
        promptTimeout = nil
        pairing.cancelPairing()
    }
}

private struct NearbyPairingPrompt: View {
    let candidate: NearbyAudioPairing.Candidate
    @ObservedObject var pairing: NearbyAudioPairing
    let close: () -> Void
    let pair: () -> Void

    var body: some View {
        VStack(spacing: 9) {
            DeviceArtwork(name: candidate.variant.model.title, variant: candidate.variant, size: 88)
            Text(candidate.variant.model.title).font(NothingType.title(23))
            Text(candidate.variant.colorName)
                .font(NothingType.body(12))
                .foregroundStyle(NothingPalette.muted)
            Text(message)
                .font(NothingType.body(12))
                .foregroundStyle(NothingPalette.muted)
                .multilineTextAlignment(.center)
                .frame(minHeight: 36)
            HStack(spacing: 9) {
                if pairing.phase != .paired {
                    Button("Not Now", action: close).buttonStyle(GreyButton())
                }
                switch pairing.phase {
                case .ready:
                    if candidate.device != nil {
                        Button("Pair", action: pair).buttonStyle(GreyButton())
                    }
                case .pairing:
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity)
                case .paired:
                    Button("Done", action: close).buttonStyle(GreyButton())
                case .needsSettings:
                    Button("Bluetooth Settings") {
                        close()
                        if let url = URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings") {
                            if let address = candidate.device?.addressString {
                                BluetoothManager.shared.rememberArtworkVariant(candidate.variant, for: address)
                            } else {
                                BluetoothManager.shared.rememberArtworkAfterBluetoothSettings(candidate.variant)
                            }
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(GreyButton())
                }
            }
        }
        .foregroundStyle(NothingPalette.text)
        .padding(18)
        .frame(width: 308, height: 262)
        .modifier(NothingMiniWindowBackground())
        .preferredColorScheme(.dark)
    }

    private var message: String {
        switch pairing.phase {
        case .ready: return "Ready to pair with this Mac."
        case .pairing: return "Pairing with this Mac…"
        case .paired: return "Paired with this Mac."
        case .needsSettings: return "Choose your device in Bluetooth Settings to finish pairing."
        }
    }
}

private struct MenuBarNavigationView: View {
    let openMainWindow: () -> Void
    let quitApp: () -> Void

    var body: some View {
        NavigationStack {
            MenuBarDashboardView(openMainWindow: openMainWindow, quitApp: quitApp)
                .navigationDestination(for: Destination.self) { destination in
                    switch destination {
                    case .equalizer: CompactEqualizerPanel()
                    case .controls: CompactControlsPanel()
                    default: CompactControlsPanel()
                    }
                }
        }
        .modifier(NothingMiniWindowBackground())
        .preferredColorScheme(.dark)
    }
}

private struct CompactEqualizerPanel: View {
    var body: some View {
        CompactPanel(title: "Equaliser") {
            EqualiserPresetGrid(compact: true)
        }
    }
}

private struct CompactControlsPanel: View {
    @ObservedObject private var bluetooth = BluetoothManager.shared

    var body: some View {
        CompactPanel(title: "Controls") {
            VStack(alignment: .leading, spacing: 14) {
                if !bluetooth.availableNoiseModes.isEmpty {
                    Text("Noise Control").font(NothingType.title(17))
                    NoiseModePicker(compact: false)
                }
                if bluetooth.supportsInEarDetection {
                    Toggle("In-ear Detection", isOn: Binding(get: { bluetooth.inEarDetection }, set: bluetooth.setInEarDetection))
                        .disabled(!bluetooth.isConnected || !bluetooth.hasReportedInEarDetection)
                }
                if bluetooth.supportsLowLatency {
                    Toggle("Low Latency Mode", isOn: Binding(get: { bluetooth.lowLatency }, set: bluetooth.setLowLatency))
                        .disabled(!bluetooth.isConnected || !bluetooth.hasReportedLowLatency)
                }
                if bluetooth.supportsGestureControls {
                    DeviceGestureEditor(showsArtwork: false)
                }
            }
            .toggleStyle(.switch)
            .tint(NothingPalette.text)
            .padding(12)
            .modifier(NothingCard(radius: 18))
        }
    }
}

private struct CompactPanel<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Button { dismiss() } label: { NothingRoundIcon(symbol: "arrow.left") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")
                Text(title).font(NothingType.title(22))
            }
            ScrollView { content.frame(maxWidth: .infinity, alignment: .leading) }
        }
        .font(NothingType.body(13))
        .foregroundStyle(NothingPalette.text)
        .padding(16)
        .frame(width: 358, height: 330)
        .navigationBarBackButtonHidden(true)
    }
}

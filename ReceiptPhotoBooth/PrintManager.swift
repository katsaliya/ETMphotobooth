import UIKit
import StarIO10   // Add via Xcode: File > Add Packages... > https://github.com/star-micronics/StarXpand-SDK-iOS

final class PrintManager: NSObject, ObservableObject {

    @Published var isPrinting = false
    @Published var lastError: String?
    @Published var discoveredPrinters: [StarPrinter] = []
    @Published var connectedPrinter: StarPrinter?

    private var manager: StarDeviceDiscoveryManager?

    // MARK: - Discovery (run this once during setup / from the admin screen)

    /// Scans for Star printers over Bluetooth, USB, and LAN. Call `stopDiscovery()`
    /// once you've found and selected the right one — you don't need to keep
    /// scanning during normal booth operation.
    func startDiscovery() {
        discoveredPrinters = []
        do {
            manager = try StarDeviceDiscoveryManagerFactory.create(interfaceTypes: [.bluetooth, .usb, .lan])
            manager?.discoveryTime = 10000 // ms
            manager?.delegate = self
            try manager?.startDiscovery()
        } catch {
            lastError = "Discovery failed: \(error.localizedDescription)"
        }
    }

    func stopDiscovery() {
        manager?.stopDiscovery()
    }

    /// Call once the user (or your saved config) has picked a printer.
    func selectPrinter(_ printer: StarPrinter) {
        connectedPrinter = printer
        var config = FrameConfigStore.shared.config
        config.savedPrinterIdentifier = printer.connectionSettings.identifier
        FrameConfigStore.shared.config = config
    }

    /// Call this on app launch (e.g. from CaptureView.onAppear) to auto-reconnect
    /// to the last-selected printer without requiring a manual rescan every time.
    func reconnectSavedPrinter() {
        guard let savedID = FrameConfigStore.shared.config.savedPrinterIdentifier else { return }
        startDiscovery()
        // Give discovery a moment to find devices, then match by saved identifier.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self else { return }
            if let match = self.discoveredPrinters.first(where: { $0.connectionSettings.identifier == savedID }) {
                self.connectedPrinter = match
            }
            self.stopDiscovery()
        }
    }

    // MARK: - Printing

    func printStrip(_ image: UIImage) {
        guard let printer = connectedPrinter else {
            lastError = "No printer connected — run discovery first"
            return
        }

        isPrinting = true
        Task {
            do {
                try await printer.open()
                defer { Task { try? await printer.close() } }

                let builder = StarXpandCommand.StarXpandCommandBuilder()
                _ = builder.addDocument(
                    StarXpandCommand.DocumentBuilder()
                        .addPrinter(
                            StarXpandCommand.PrinterBuilder()
                                .actionPrintImage(
                                    StarXpandCommand.PrintImageParameter(
                                        image: image,
                                        width: Int(StripComposer.printWidth)
                                    )
                                )
                                .actionCut(.partial)
                        )
                )

                let commands = builder.getCommands()
                try await printer.print(command: commands)

                await MainActor.run { self.isPrinting = false }
            } catch {
                await MainActor.run {
                    self.isPrinting = false
                    self.lastError = "Print failed: \(error.localizedDescription)"
                }
            }
        }
    }
}

extension PrintManager: StarDeviceDiscoveryManagerDelegate {
    func manager(_ manager: StarDeviceDiscoveryManager, didFind printer: StarPrinter) {
        DispatchQueue.main.async {
            if !self.discoveredPrinters.contains(where: { $0.connectionSettings.identifier == printer.connectionSettings.identifier }) {
                self.discoveredPrinters.append(printer)
            }
        }
    }

    func managerDidFinishDiscovery(_ manager: StarDeviceDiscoveryManager) {
        // Discovery window closed. If nothing showed up, check the printer
        // is powered on and paired/connected in iPad Settings > Bluetooth first.
    }
}

import UIKit
import StarIO10   // Add via Xcode: File > Add Packages... > https://github.com/star-micronics/StarXpand-SDK-iOS
import Combine

final class PrintManager: NSObject, ObservableObject {

    @Published var isPrinting = false
    @Published var isConnecting = false
    @Published var lastError: String?
    @Published var discoveredPrinters: [StarPrinter] = []
    @Published var connectedPrinter: StarPrinter?

    private var manager: StarDeviceDiscoveryManager?

    // MARK: - Discovery

    /// Scans for Star printers over Bluetooth, USB, and LAN.
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
        lastError = nil
        var config = FrameConfigStore.shared.config
        config.savedPrinterIdentifier = printer.connectionSettings.identifier
        FrameConfigStore.shared.config = config
    }

    /// Fully automatic connection. Since there's only ever one Star
    /// printer plugged into the booth, this just connects to whichever
    /// one it finds: tries the last-known printer first (fast, usually
    /// the same one), and if that's not found within a couple seconds,
    /// falls back to connecting to the first printer discovered at all
    /// (handles the very first run, or a swapped-out printer).
    func autoConnect(force: Bool = false) {
        guard force || connectedPrinter == nil else { return } // already connected
        if force { connectedPrinter = nil }

        isConnecting = true
        lastError = nil
        let savedID = FrameConfigStore.shared.config.savedPrinterIdentifier
        startDiscovery()

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.connectedPrinter == nil else { return }

            if let savedID, let match = self.discoveredPrinters.first(where: { $0.connectionSettings.identifier == savedID }) {
                self.selectPrinter(match)
            } else if let first = self.discoveredPrinters.first {
                self.selectPrinter(first)
            } else {
                self.lastError = "No printer found"
            }
            self.stopDiscovery()
            self.isConnecting = false
        }
    }

    /// Manually disconnect — clears the current connection and forgets
    /// the saved printer identifier, so autoConnect() won't immediately
    /// reconnect to it. Used from the printer management screen.
    func disconnect() {
        connectedPrinter = nil
        var config = FrameConfigStore.shared.config
        config.savedPrinterIdentifier = nil
        FrameConfigStore.shared.config = config
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
                                    StarXpandCommand.Printer.ImageParameter(
                                        image: image,
                                        width: Int(StripComposer.printWidth)
                                    )
                                    // Error-diffusion dithering instead of a hard
                                    // black/white threshold — preserves the grayscale
                                    // midtones from BoothFilter so the print matches
                                    // what's shown on screen instead of crushing to
                                    // solid black blobs.
                                    .setEffectDiffusion(true)
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

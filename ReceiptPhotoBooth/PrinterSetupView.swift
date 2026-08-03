import SwiftUI
import StarIO10

struct PrinterSetupView: View {
    @ObservedObject var printer: PrintManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if printer.discoveredPrinters.isEmpty {
                    Text("Searching for printers…")
                        .foregroundStyle(.secondary)
                }
                ForEach(printer.discoveredPrinters, id: \.connectionSettings.identifier) { device in
                    Button {
                        printer.selectPrinter(device)
                        printer.stopDiscovery()
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(device.connectionSettings.identifier)
                                Text(device.connectionSettings.interfaceType.rawValue.uppercased())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if printer.connectedPrinter?.connectionSettings.identifier == device.connectionSettings.identifier {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Printer")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { printer.stopDiscovery(); dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Rescan") { printer.startDiscovery() }
                }
            }
            .onAppear { printer.startDiscovery() }
        }
    }
}

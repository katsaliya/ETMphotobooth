import SwiftUI
import PhotosUI

struct FrameSettingsView: View {
    @ObservedObject private var store = FrameConfigStore.shared
    @ObservedObject var printer: PrintManager = PrintManager()
    @Environment(\.dismiss) private var dismiss
    @State private var selectedLogoItem: PhotosPickerItem?
    @State private var showPrinterSetup = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Printer") {
                    Button(printer.connectedPrinter == nil ? "Connect printer…" : "Change printer…") {
                        showPrinterSetup = true
                    }
                    if let connected = printer.connectedPrinter {
                        Text(connected.connectionSettings.identifier)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Text") {
                    TextField("Header", text: $store.config.headerText)
                    TextField("Footer", text: $store.config.footerText)
                    Toggle("Show date & time", isOn: $store.config.showDateTime)
                    Toggle("Show border around photos", isOn: $store.config.showBorder)
                }

                Section("Logo") {
                    PhotosPicker("Choose logo image", selection: $selectedLogoItem, matching: .images)
                    if let data = store.config.logoImageData, let img = UIImage(data: data) {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 60)
                        Button("Remove logo", role: .destructive) {
                            store.config.logoImageData = nil
                        }
                    }
                }

                Section("Sequence") {
                    Stepper("Photos per session: \(store.config.shotCount)",
                            value: $store.config.shotCount, in: 1...8)
                    Stepper(String(format: "Seconds between shots: %.1f", store.config.secondsBetweenShots),
                            value: $store.config.secondsBetweenShots, in: 1...6, step: 0.5)
                }

                Section {
                    Text("These settings only affect what gets printed. Guests only ever see the single capture button — this screen is admin-only.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Frame Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: selectedLogoItem) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self) {
                        store.config.logoImageData = data
                    }
                }
            }
            .sheet(isPresented: $showPrinterSetup) {
                PrinterSetupView(printer: printer)
            }
        }
    }
}

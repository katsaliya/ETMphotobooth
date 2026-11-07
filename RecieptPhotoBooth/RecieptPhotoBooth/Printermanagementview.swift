//
//  Printermanagementview.swift
//  RecieptPhotoBooth
//
//  Created by Kataliya Sungkamee on 8/9/26.
//
import SwiftUI
import StarIO10

/// Reached by tapping the elephant logo. Lets whoever's managing the
/// booth see connection status, rescan for the printer, pick a specific
/// one if multiple show up, or disconnect entirely.
struct PrinterManagementView: View {
    @ObservedObject var printer: PrintManager
    @ObservedObject private var frameStore = FrameConfigStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Circle()
                            .fill(printer.connectedPrinter != nil ? Color.green : Color.red)
                            .frame(width: 10, height: 10)
                        Text(printer.connectedPrinter != nil ? "Connected" : "Not connected")
                            .font(.epilogue(size: 16, weight: .light))
                        Spacer()
                        if printer.isConnecting {
                            ProgressView()
                        }
                    }
                    if let connected = printer.connectedPrinter {
                        Text(connected.connectionSettings.identifier)
                            .font(.epilogue(size: 12, weight: .light))
                            .foregroundStyle(.secondary)
                    }
                    if let error = printer.lastError {
                        Text(error)
                            .font(.epilogue(size: 12, weight: .light))
                            .foregroundStyle(.red)
                    }
                }

                Section("Available Printers") {
                    if printer.discoveredPrinters.isEmpty {
                        Text(printer.isConnecting ? "Searching…" : "No printers found yet")
                            .font(.epilogue(size: 14, weight: .light))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(printer.discoveredPrinters, id: \.connectionSettings.identifier) { device in
                        Button {
                            printer.selectPrinter(device)
                            printer.stopDiscovery()
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(device.connectionSettings.identifier)
                                        .font(.epilogue(size: 14, weight: .light))
                                        .foregroundStyle(.primary)
                                    Text("\(device.connectionSettings.interfaceType)".uppercased())
                                        .font(.epilogue(size: 11, weight: .light))
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

                Section {
                    Stepper(value: runUpBinding, in: FrameConfig.liveRunUpRange, step: 0.25) {
                        Text("Run-up before each photo: \(runUpBinding.wrappedValue, specifier: "%.2g") s")
                            .font(.epilogue(size: 14, weight: .light))
                    }
                    Stepper(value: freezeBinding, in: FrameConfig.liveFreezeRange, step: 0.25) {
                        Text("Freeze on each photo: \(freezeBinding.wrappedValue, specifier: "%.2g") s")
                            .font(.epilogue(size: 14, weight: .light))
                    }
                } header: {
                    Text("Live video")
                } footer: {
                    Text("Saved with the color strip in Files → On My iPad → Booth By Liya → Sessions.")
                }

                Section {
                    Button("Rescan") {
                        printer.autoConnect(force: true)
                    }
                    if printer.connectedPrinter != nil {
                        Button("Disconnect", role: .destructive) {
                            printer.disconnect()
                        }
                    }
                }
            }
            .navigationTitle("Printer")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        printer.stopDiscovery()
                        dismiss()
                    }
                }
            }
            .onAppear {
                printer.startDiscovery()
            }
        }
    }

    private var runUpBinding: Binding<Double> {
        Binding(
            get: { frameStore.config.resolvedLiveRunUpSeconds },
            set: { frameStore.config.liveRunUpSeconds = $0 }
        )
    }

    private var freezeBinding: Binding<Double> {
        Binding(
            get: { frameStore.config.resolvedLiveFreezeSeconds },
            set: { frameStore.config.liveFreezeSeconds = $0 }
        )
    }
}

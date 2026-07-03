import LinxCGMKit
import LoopKit
import LoopKitUI
import SwiftUI

struct LinxSettingsView: View {
    @ObservedObject var viewModel: LinxSettingsViewModel
    var didFinish: () -> Void
    var deleteCGM: () -> Void

    @State private var refInput: String = ""
    @State private var showDeleteConfirm = false

    var body: some View {
        List {
            statusSection
            serialSection
            nearbySection
            calibrationSection
            deleteSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Linx CGM")
        .navigationBarItems(trailing: Button("Done", action: didFinish))
        .onAppear { viewModel.startScanning() }
    }

    private var statusSection: some View {
        Section(header: Text("Status")) {
            HStack {
                Text("Last reading")
                Spacer()
                Text(viewModel.latestGlucoseText).foregroundColor(.secondary)
            }
            HStack {
                Text("Scanner")
                Spacer()
                Text(viewModel.statusText)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            Text("The Loop updates about every 3 minutes with a new Linx reading.")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
    }

    private var serialSection: some View {
        Section(
            header: Text("Sensor serial number"),
            footer: Text("E.g. LinX-2222296PN2. Leave blank to listen to any Linx sensor. Filters on partial match.")
        ) {
            TextField("LinX-…", text: $viewModel.sensorSerial)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            Button("Save serial number") {
                viewModel.saveSerial()
            }
        }
    }

    // MARK: - Picker: nearby Linx sensors (names containing "Linx" only)

    private var nearbySection: some View {
        Section(
            header: Text("Nearby Linx sensors"),
            footer: Text("Tap a sensor to listen to only that one. Useful when several Linx sensors are in range.")
        ) {
            if viewModel.nearbyDevices.isEmpty {
                HStack {
                    Text("Searching…")
                        .foregroundColor(.secondary)
                    Spacer()
                    ProgressView()
                }
            } else {
                ForEach(viewModel.nearbyDevices) { device in
                    Button {
                        viewModel.selectDevice(device)
                    } label: {
                        HStack(spacing: 12) {
                            Image(
                                systemName: device.name == viewModel.sensorSerial
                                    ? "checkmark.circle.fill" : "circle"
                            )
                            .foregroundColor(device.name == viewModel.sensorSerial ? .accentColor : .secondary)
                            deviceNameLabel(device.name)
                            Spacer()
                            rssiLabel(device.rssi)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Shows the full name with the last 2 characters in bold.
    private func deviceNameLabel(_ name: String) -> some View {
        let head = name.count > 2 ? String(name.dropLast(2)) : ""
        let tail = name.count >= 2 ? String(name.suffix(2)) : name
        return (
            Text(head).foregroundColor(.primary)
                + Text(tail).bold().foregroundColor(.accentColor)
        )
        .lineLimit(1)
        .truncationMode(.middle)
    }

    /// Signal strength with a small icon and dBm value.
    private func rssiLabel(_ rssi: Int) -> some View {
        HStack(spacing: 4) {
            Image(
                systemName: rssi >= -60 ? "wifi"
                    : (rssi >= -75 ? "wifi" : "wifi.exclamationmark")
            )
            .font(.caption)
            Text("\(rssi) dBm")
                .font(.caption)
        }
        .foregroundColor(.secondary)
    }

    private var calibrationSection: some View {
        Section(
            header: Text("Two-point calibration"),
            footer: Text(
                "Enter the current reference blood glucose (fingerstick or Dexcom). 2 different points set an accurate slope + offset. The raw signal comes from the sensor."
            )
        ) {
            // Active curve
            HStack {
                Text("Active curve")
                Spacer()
                Text(String(format: "mmol = %.5f·raw + %.3f", viewModel.calA, viewModel.calB))
                    .font(.footnote.monospaced())
                    .foregroundColor(.secondary)
            }

            // Current raw value
            if let raw = viewModel.currentRaw10 {
                HStack {
                    Text("Current raw (raw10)")
                    Spacer()
                    Text("\(raw)").foregroundColor(.secondary)
                }
            } else {
                Text("Waiting for first reading…")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            // Recorded points
            if viewModel.calPoints.isEmpty {
                Text("No calibration points (factory defaults).")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                ForEach(Array(viewModel.calPoints.enumerated()), id: \.offset) { _, p in
                    HStack {
                        Text("raw \(p.glu10)")
                        Spacer()
                        Text(String(format: "%.1f mmol/L", p.mmol)).foregroundColor(.secondary)
                    }
                    .font(.footnote)
                }
            }

            // Record new point
            HStack {
                TextField("Ref mmol/L", text: $refInput)
                    .keyboardType(.decimalPad)
                Button("Record") {
                    if let v = Double(refInput.replacingOccurrences(of: ",", with: ".")) {
                        viewModel.addCalibration(refMmol: v)
                        refInput = ""
                    }
                }
                .disabled(viewModel.currentRaw10 == nil || refInput.isEmpty)
            }

            Button(role: .destructive) {
                viewModel.resetCalibration()
            } label: {
                Text("Reset calibration (factory defaults)")
            }
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                HStack {
                    Spacer()
                    Text("Delete Linx CGM")
                    Spacer()
                }
            }
            .confirmationDialog(
                "Are you sure you want to delete Linx CGM?",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive, action: deleteCGM)
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}

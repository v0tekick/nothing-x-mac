//
//  BatteryIndicatorView.swift
//  Nothing X MacOS
//
//  Created by Arunavo Ray on 15/02/23.
//

import SwiftUI

struct BatteryIndicatorView: View {
    @ObservedObject private var bluetooth = BluetoothManager.shared

    var body: some View {
        HStack(spacing: 10) {
            battery(bluetooth.leftBattery, label: "L")
            battery(bluetooth.caseBattery, label: "C")
            battery(bluetooth.rightBattery, label: "R")
        }
        .frame(width: 170)
    }

    private func battery(_ value: Int?, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value.map { "\($0)% \(label)" } ?? "-- \(label)")
                .font(.system(size: 12, weight: .light))
                .foregroundColor(.white.opacity(0.8))
            ProgressView(value: Double(value ?? 0), total: 100)
                .progressViewStyle(NothingProgressViewStyle())
                .opacity(value == nil ? 0.35 : 1)
        }
    }
}

struct BatteryIndicatorView_Previews: PreviewProvider {
    static let store = Store()
    static var previews: some View {
        BatteryIndicatorView()
    }
}

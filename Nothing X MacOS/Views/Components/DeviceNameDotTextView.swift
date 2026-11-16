//
//  DeviceNameDotTextView.swift
//  Nothing X MacOS
//
//  Created by Arunavo Ray on 15/02/23.
//

import SwiftUI

struct DeviceNameDotTextView: View {
    @ObservedObject private var bluetooth = BluetoothManager.shared

    var body: some View {
        VStack {
            Spacer(minLength: 5)
            Text(bluetooth.isConnected ? bluetooth.deviceName : "NOTHING X")
                .font(NothingType.dot(20))
                .foregroundStyle(NothingPalette.text)
                .rotationEffect(.degrees(-90))
                .padding()
                .fixedSize()
                .frame(width: 14, height: 66)
            Spacer(minLength: 150)
        }
    }
}

struct DeviceNameDotTextView_Previews: PreviewProvider {
    static var previews: some View {
        DeviceNameDotTextView()
    }
}

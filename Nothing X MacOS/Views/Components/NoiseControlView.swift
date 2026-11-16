//
//  NoiseControlView.swift
//  Nothing X MacOS
//
//  Created by Arunavo Ray on 15/02/23.
//

import SwiftUI

struct NoiseControlView: View {
    @ObservedObject private var bluetooth = BluetoothManager.shared

    var body: some View {
        // NOISE CONTROL
        VStack(alignment: .center) {

            Text("NOISE CONTROL · \(bluetooth.isConnected ? bluetooth.noiseMode.uppercased() : "DISCONNECTED")")
                .font(.system(size: 10, weight: .regular))
                .foregroundColor(.white.opacity(0.8))

            Spacer()

            //ANC Buttons
            VStack {

                ZStack {
                    // Background
                    RoundedRectangle(cornerRadius: 100)
                        .fill(Color(#colorLiteral(red: 0.10980392247438431, green: 0.11372549086809158, blue: 0.12156862765550613, alpha: 1)))
                        .frame(width: 180, height: 34)

                    // 3 buttons
                    HStack(spacing: 5) {
                        ForEach(NoiseControlOptions.allCases) { option in
                            Button(action: {
                                bluetooth.setNoiseControl(option.id)
                            }) {
                                Image(systemName: option.icon)
                            }
                            .buttonStyle(ANCButton(selected: bluetooth.noiseMode == option.id))
                            .disabled(!bluetooth.isConnected)
                        }
                    }
                    .fixedSize()
                    .frame(width: 180, height: 34)
                }

            }

        }
        .frame(width: 200, height: 60)
    }
}

struct NoiseControlView_Previews: PreviewProvider {
    static let store = Store()
    static var previews: some View {
        NoiseControlView()
    }
}

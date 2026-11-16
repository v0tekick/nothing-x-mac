//
//  ConnectView.swift
//  Nothing X MacOS
//
//  Created by Arunavo Ray on 14/02/23.
//

import SwiftUI

struct ConnectView: View {
    var body: some View {
        HStack {
            Spacer(minLength: 5)

            // ear (1)
            DeviceNameDotTextView()

            VStack {

                HStack {
                    Spacer()

                    // Settings
                    SettingsButtonView()
                }

                VStack {
                    // Ear 1 Image
                    DeviceArtwork(name: "Nothing Ear (1)", size: 92)

                    Spacer(minLength: 15)

                    // Connect Button
                    Button("CONNECT") {
                        BluetoothManager.shared.reconnect()
                    }
                    .buttonStyle(OffWhiteConnectButton())

                    Spacer(minLength: 15)
                }

            }
        }
        .padding(4)
        .background(.black)
        .cornerRadius(8)
    }

}

struct ConnectView_Previews: PreviewProvider {
    static var previews: some View {
        ConnectView()
    }
}

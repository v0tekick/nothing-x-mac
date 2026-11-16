//
//  SettingsButtonView.swift
//  Nothing X MacOS
//
//  Created by Arunavo Ray on 15/02/23.
//

import SwiftUI

struct SettingsButtonView: View {
    var body: some View {
        NavigationLink(value: Destination.settings) {
            NothingRoundIcon(symbol: "gearshape")
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Settings")
        .help("Settings")
    }
}

struct SettingsButtonView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsButtonView()
    }
}

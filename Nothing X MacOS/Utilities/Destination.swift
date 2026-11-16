//
//  Destination.swift
//  Nothing X MacOS
//
//  Created by Arunavo Ray on 21/02/23.
//

import Foundation


enum Destination: String, CaseIterable, Hashable {
    case home = "home"
    case devices = "devices"
    case equalizer = "equalizer"
    case controls = "controls"
    case settings = "settings"
    case bassEnhance
    case personalSound
    case dualConnection
    case audioDeviceSettings
    case aboutDevice
    case findMyBuds = "findMyBuds"
}

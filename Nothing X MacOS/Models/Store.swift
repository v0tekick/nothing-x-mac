//
//  Store.swift
//  Nothing X MacOS
//
//  Created by Arunavo Ray on 21/02/23.
//

import Foundation
import CoreGraphics

enum PopupWindowShape: String, CaseIterable, Identifiable, Hashable {
    case landscape = "4:3"
    case square = "Square"

    var id: String { rawValue }

    var size: CGSize {
        switch self {
        case .landscape:
            return CGSize(width: 960, height: 720)
        case .square:
            return CGSize(width: 820, height: 820)
        }
    }
}


enum EarBudSide: String, CaseIterable, Identifiable, Hashable {
    case left
    case right

    var id: String { self.rawValue }
}

enum NoiseControlOptions: String, CaseIterable, Identifiable, Hashable {
    case anc
    case transparency
    case off

    var icon: String {
        switch self {
            case .anc:
                return "person.crop.circle"
            case .transparency:
                return "person.and.background.dotted"
            case .off:
                return "person.crop.circle.dashed"
        }
    }

    var id: String { self.rawValue }
}

class Store: ObservableObject {
    @Published var windowShape: PopupWindowShape {
        didSet { UserDefaults.standard.set(windowShape.rawValue, forKey: "popupWindowShape") }
    }

    init() {
        let savedShape = UserDefaults.standard.string(forKey: "popupWindowShape")
        windowShape = PopupWindowShape(rawValue: savedShape ?? "4:3") ?? .landscape
    }


    @Published var earBudSelectedSide = EarBudSide.left.rawValue

}

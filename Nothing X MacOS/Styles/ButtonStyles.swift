//
//  ButtonStyles.swift
//  Nothing X MacOS
//
//  Created by Arunavo Ray on 13/02/23.
//

import Foundation
import SwiftUI

struct NothingGlassSurface<Surface: Shape>: ViewModifier {
    let shape: Surface
    var fallback = NothingPalette.panel
    var interactive = true
    var tint: Color? = nil

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), !reduceTransparency {
            content.glassEffect(.regular.tint(tint).interactive(interactive && isEnabled), in: shape)
        } else {
            content.background(fallback, in: shape)
        }
    }
}

struct NothingGlassGroup<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if #available(macOS 26.0, *), !reduceTransparency {
            GlassEffectContainer(spacing: 4) { content }
        } else {
            content
        }
    }
}

struct NothingMiniWindowBackground: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content.background {
            if reduceTransparency {
                NothingPalette.ink
            } else {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(NothingPalette.ink.opacity(0.96))
            }
        }
    }
}

struct NothingMainWindowBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency {
            NothingPalette.ink
        } else {
            FrostedBackdrop().overlay(NothingPalette.ink.opacity(0.96))
        }
    }

    private struct FrostedBackdrop: NSViewRepresentable {
        func makeNSView(context: Context) -> NSVisualEffectView {
            let view = NSVisualEffectView()
            view.material = .underWindowBackground
            view.blendingMode = .behindWindow
            view.state = .active
            return view
        }

        func updateNSView(_ view: NSVisualEffectView, context: Context) {}
    }
}

struct GreyButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, minHeight: 48)
            .font(NothingType.title(15))
            .foregroundStyle(NothingPalette.text)
            .background(NothingPalette.raised, in: Capsule())
            .overlay(Capsule().stroke(NothingPalette.line, lineWidth: 1))
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}


struct GreyImageButtonCicle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 28, height: 28)
            .background(NothingPalette.raised)
            .clipShape(Circle())
    }
}


struct BlackImageButtonCicle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 28, height: 28)
            .background(.black)
            .clipShape(Circle())
    }
}

struct BlackImageButtonCicleLarge: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 50, height: 50)
            .background(.black)
            .clipShape(Circle())
    }
}


struct OffWhiteConnectButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 20)
            .frame(minHeight: 46)
            .background(NothingPalette.text)
            .font(.system(size: 11, weight: .medium)).foregroundStyle(NothingPalette.ink)
            .clipShape(Capsule())
    }
}

struct ANCButton: ButtonStyle {
    var selected: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        if(selected) {
            configuration.label
                .padding(4)
                .frame(width: 56, height: 40)
                .background(NothingPalette.text)
                .font(.system(size: 14, weight:.regular)).foregroundStyle(NothingPalette.ink)
                .clipShape(Capsule())
        }
        else {
            configuration.label
                .padding(4)
                .frame(width: 56, height: 40)
                .background(NothingPalette.raised)

                .font(.system(size: 14, weight:.regular)).foregroundStyle(NothingPalette.text)
                .clipShape(Capsule())
        }
    }
}

struct FindMyTransparentButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        return HStack {
            configuration.label
                .font(.system(size: 10, weight: .medium, design: .monospaced))
            Spacer()
            Image(systemName: "arrow.right")
                .padding(.trailing, 10)
        }
        .frame(maxWidth: .infinity, minHeight: 42)
        .background(NothingPalette.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(0)
    }
}

struct ControlTapButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(10)
            .padding(.leading, 6)
            .background(NothingPalette.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(NothingPalette.text)
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(NothingPalette.line, lineWidth: 1))
    }
}

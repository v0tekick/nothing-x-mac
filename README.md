# Nothing X for Mac

An unofficial macOS companion for Nothing and CMF audio devices, based on [Arunavo Ray’s Nothing X macOS project](https://github.com/arunavo4/nothing-x-macos). The app has a resizable main window and a menu-bar panel for battery and quick controls. Closing the main window leaves the menu-bar app running. Select **Close App** in the menu bar to quit.

## Install

1. Download `Nothing-X-Mac-1.0.0-universal.dmg` from the latest GitHub release.
2. Open the disk image and drag **Nothing X** to **Applications**.
3. Launch the app, allow Bluetooth access, and connect your device. You can pair using the nearby prompt when it appears or through macOS Bluetooth settings.

The app targets macOS 13 and later and includes Apple silicon and Intel builds. Liquid Glass runs on macOS 26 and later. The initial public release is ad-hoc signed and has no Apple notarization. macOS may require first-launch approval. [Apple’s first-launch guidance](https://support.apple.com/en-us/102445)

## Device support

- **Nothing earbuds** — Ear (1), Ear (Stick), Ear (2), Ear (2024), Ear (a), Ear (open), Ear (3), and Ear (3a).
- **Nothing headphones** — Headphone (1), Headphone (a), and Headphone (1) Pro.
- **CMF audio** — Buds Pro, Neckband Pro, Buds, Buds Pro 2, Buds 2, Buds 2 Plus, Buds 2a, Headphone Pro, Clip Pro, Buds Neo, Speaker S, and Speaker M.

The catalog contains 23 models and 76 Fast Pair identifiers. Depending on device and firmware, controls include battery level, ANC and transparency, EQ, Bass Enhance, Dual Connection, low latency, in-ear detection, gesture assignments, and find-device tones. The app reads existing settings on connection and writes changes when you use the controls.

Ear (2024) and CMF Buds Pro 2 were hardware-tested during development. The remaining models need live verification. Speaker S and Speaker M are included for discovery and pairing, with companion controls still to be verified. Watches are outside this release.

## Build

Open `Nothing X MacOS.xcodeproj` and build the `Nothing X MacOS` scheme with Xcode 26 or later. To produce an ad-hoc-signed universal disk image, run:

```sh
./scripts/package-macos.sh
```

The source tree includes the Swift code, Xcode project, device catalog, and original app icon. The public build uses system fonts and symbols in place of the Android artwork and fonts. The Android package is unnecessary to build the app.

Bluetooth protocol references include [ear-web](https://github.com/radiance-project/ear-web), [Nothing X Mac protocol notes](https://github.com/Senooy/nothing-x-mac/blob/main/Protocol.md), and [NT Link hardware captures](https://github.com/ncr/omarchy-headphones/blob/main/PROTOCOL.md#nothing-nt-link--the-nothing-x-protocol-on-rfcomm-channel-15-or-28).

The source code is distributed under the [GNU GPL v3](LICENSE). Nothing and CMF product names identify compatible devices. This project is independent of Nothing Technology Limited.

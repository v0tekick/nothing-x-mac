import SwiftUI

struct BudsSidePickerView: View {
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(EarBudSide.allCases) { side in
                let selected = selection == side.rawValue
                Button { selection = side.rawValue } label: {
                    Text(side.rawValue.capitalized)
                        .font(NothingType.title(15))
                        .foregroundStyle(selected ? NothingPalette.ink : NothingPalette.text)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background {
                            if selected { Capsule().fill(NothingPalette.text) }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(NothingPalette.panel, in: Capsule())
    }
}

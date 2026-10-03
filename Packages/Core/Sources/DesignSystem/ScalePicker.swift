import SwiftUI

/// 1...5 selector (mood, stress, energy).
public struct ScalePicker: View {
    private let title: String
    private let lowLabel: String
    private let highLabel: String
    @Binding private var value: Int

    public init(title: String, lowLabel: String, highLabel: String, value: Binding<Int>) {
        self.title = title
        self.lowLabel = lowLabel
        self.highLabel = highLabel
        self._value = value
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: FormaSpacing.s) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(FormaColor.ink)
            HStack(spacing: FormaSpacing.s) {
                ForEach(1...5, id: \.self) { n in
                    let selected = n == value
                    Button {
                        value = n
                    } label: {
                        Text("\(n)")
                            .font(.formaNumber(20))
                            .foregroundStyle(selected ? FormaColor.onVolt : FormaColor.ink)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(selected ? FormaColor.volt : FormaColor.well,
                                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(selected ? Color.clear : FormaColor.line, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(title) \(n) z 5")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            HStack {
                Text(lowLabel)
                Spacer()
                Text(highLabel)
            }
            .font(.system(size: 13))
            .foregroundStyle(FormaColor.ink3)
        }
    }
}

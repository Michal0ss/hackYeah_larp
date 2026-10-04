import SwiftUI

/// A search box: magnifier, the text, and a button that clears it.
public struct FormaSearchField: View {
    private let placeholder: String
    @Binding private var text: String
    @FocusState private var focused: Bool

    public init(placeholder: String, text: Binding<String>) {
        self.placeholder = placeholder
        self._text = text
    }

    private var field: some View {
        let base = TextField(placeholder, text: $text, prompt: Text(placeholder).foregroundStyle(FormaColor.ink3))
            .focused($focused)
            .font(.system(size: 17))
            .foregroundStyle(FormaColor.ink)
            .autocorrectionDisabled()
            .submitLabel(.search)
        #if os(iOS)
        return base.textInputAutocapitalization(.never)
        #else
        return base
        #endif
    }

    public var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(FormaColor.ink3)
                .accessibilityHidden(true)
            field
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 18)).foregroundStyle(FormaColor.ink3)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Wyczyść wyszukiwanie")
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .background(FormaColor.well, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(focused ? FormaColor.voltText : FormaColor.wellLine, lineWidth: focused ? 2 : 1)
        }
    }
}

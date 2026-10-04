import SwiftUI

/// Round tinted icon, used in tiles, banners and list rows.
public struct IconBadge: View {
    private let systemImage: String
    private let fill: Color
    private let icon: Color
    private let size: CGFloat

    /// - Parameters:
    ///   - fill: base color of the tinted circle.
    ///   - icon: readable color of the glyph (use the `...Text` variants from `FormaColor`).
    public init(systemImage: String, fill: Color = FormaColor.volt, icon: Color = FormaColor.voltText, size: CGFloat = 40) {
        self.systemImage = systemImage
        self.fill = fill
        self.icon = icon
        self.size = size
    }

    public var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(icon)
            .frame(width: size, height: size)
            .background(fill.opacity(0.15), in: Circle())
            .overlay { Circle().strokeBorder(fill.opacity(0.36), lineWidth: 1) }
            .accessibilityHidden(true)
    }
}

/// Large single- or multi-choice tile (goal, equipment).
public struct SelectableTile: View {
    private let title: String
    private let subtitle: String?
    private let systemImage: String
    private let isSelected: Bool
    private let minHeight: CGFloat
    private let action: () -> Void

    public init(title: String, subtitle: String? = nil, systemImage: String, isSelected: Bool,
                minHeight: CGFloat = 132, action: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.minHeight = minHeight
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                IconBadge(systemImage: systemImage, size: 44)
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(FormaColor.ink)
                    .multilineTextAlignment(.leading)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(FormaColor.ink2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
            .glassCard(radius: 26)
            .overlay {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(isSelected ? FormaColor.voltText : .clear, lineWidth: 2)
            }
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(FormaColor.onVolt)
                        .frame(width: 26, height: 26)
                        .background(FormaColor.volt, in: Circle())
                        .padding(12)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(.formaPress)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Capsule choice (level, days, minutes, body areas).
public struct PillOption: View {
    private let title: String
    private let isSelected: Bool
    private let showsCheck: Bool
    private let expands: Bool
    private let action: () -> Void

    public init(_ title: String, isSelected: Bool, showsCheck: Bool = false, expands: Bool = false,
                action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.showsCheck = showsCheck
        self.expands = expands
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isSelected && showsCheck {
                    Image(systemName: "checkmark").font(.system(size: 13, weight: .heavy))
                }
                Text(title).lineLimit(1).minimumScaleFactor(0.8)
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(isSelected ? FormaColor.onVolt : FormaColor.ink)
            .padding(.horizontal, 16)
            .frame(maxWidth: expands ? .infinity : nil, minHeight: 44)
            .background(isSelected ? FormaColor.volt : FormaColor.well, in: Capsule())
            .overlay { Capsule().strokeBorder(isSelected ? .clear : FormaColor.wellLine, lineWidth: 1) }
            .shadow(color: FormaColor.volt.opacity(isSelected ? 0.35 : 0), radius: 10, y: 6)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(.formaPress)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// "Tak / Nie" switch for screening questions. `nil` means not answered.
public struct YesNoControl: View {
    private let selection: Bool?
    private let label: String
    private let onSelect: (Bool) -> Void

    public init(selection: Bool?, label: String, onSelect: @escaping (Bool) -> Void) {
        self.selection = selection
        self.label = label
        self.onSelect = onSelect
    }

    public var body: some View {
        HStack(spacing: 2) {
            segment("Tak", value: true, fill: FormaColor.moderate, text: Color(hex: 0x1A1203))
            segment("Nie", value: false, fill: FormaColor.volt, text: FormaColor.onVolt)
        }
        .padding(2)
        .background(FormaColor.well, in: Capsule())
        .overlay { Capsule().strokeBorder(FormaColor.wellLine, lineWidth: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    private func segment(_ title: String, value: Bool, fill: Color, text: Color) -> some View {
        let selected = selection == value
        return Button {
            onSelect(value)
        } label: {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(selected ? text : FormaColor.ink2)
                .frame(minWidth: 54, minHeight: 44)
                .padding(.horizontal, 4)
                .background(selected ? fill : .clear, in: Capsule())
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selected)
        }
        .buttonStyle(.formaPress)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Thin progress bar made of equal segments ("Krok 3 z 6").
public struct SegmentedProgress: View {
    private let total: Int
    private let current: Int

    /// - Parameter current: 1-based index of the current segment. Segments up to it are filled.
    public init(total: Int, current: Int) {
        self.total = total
        self.current = current
    }

    public var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index < current ? FormaColor.volt : FormaColor.ink.opacity(0.14))
                    .frame(height: 5)
            }
        }
        .animation(.easeOut(duration: 0.3), value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Krok \(current) z \(total)")
    }
}

/// Short note with an icon, on a glass card.
public struct InfoBanner<Content: View>: View {
    private let systemImage: String
    private let tint: Color
    private let content: Content

    public init(systemImage: String, tint: Color = FormaColor.restText, @ViewBuilder content: () -> Content) {
        self.systemImage = systemImage
        self.tint = tint
        self.content = content()
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
                .padding(.top, 1)
                .accessibilityHidden(true)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glassCard(radius: 22)
    }
}

/// Single-line text input in the hackGYM style.
public struct FormaTextField: View {
    private let title: String
    private let placeholder: String
    @Binding private var text: String
    @FocusState private var focused: Bool

    public init(_ title: String, placeholder: String, text: Binding<String>) {
        self.title = title
        self.placeholder = placeholder
        self._text = text
    }

    public var body: some View {
        TextField(title, text: $text, prompt: Text(placeholder).foregroundStyle(FormaColor.ink3))
            .focused($focused)
            .font(.system(size: 17))
            .foregroundStyle(FormaColor.ink)
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .background(FormaColor.well, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(focused ? FormaColor.voltText : FormaColor.wellLine, lineWidth: focused ? 2 : 1)
            }
    }
}

/// Glass card whose header expands to reveal more (health history sections).
public struct DisclosureCard<Content: View>: View {
    private let title: String
    private let summary: String
    private let systemImage: String
    private let fill: Color
    private let icon: Color
    @Binding private var isExpanded: Bool
    private let content: Content

    public init(title: String, summary: String, systemImage: String, fill: Color, icon: Color,
                isExpanded: Binding<Bool>, @ViewBuilder content: () -> Content) {
        self.title = title
        self.summary = summary
        self.systemImage = systemImage
        self.fill = fill
        self.icon = icon
        self._isExpanded = isExpanded
        self.content = content()
    }

    public var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 12) {
                    IconBadge(systemImage: systemImage, fill: fill, icon: icon)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(FormaColor.ink)
                        Text(summary).font(.system(size: 13)).foregroundStyle(FormaColor.ink2)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(FormaColor.ink3)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
            .accessibilityValue(isExpanded ? "Rozwinięte" : "Zwinięte")

            if isExpanded {
                content
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .glassCard()
    }
}

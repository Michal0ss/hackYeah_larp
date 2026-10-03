import Foundation

public enum OnboardingStep: Int, CaseIterable, Sendable {
    case goal = 1, aboutYou, equipment, medicalHistory, screening, appleHealth, generating

    /// Steps the user sees as "Krok N z 6".
    public static let numberedCount = 6

    public var number: Int? { self == .generating ? nil : rawValue }

    public var label: String? {
        number.map { "Krok \($0) z \(Self.numberedCount)" }
    }

    public var next: OnboardingStep? { Self(rawValue: rawValue + 1) }
    public var previous: OnboardingStep? { Self(rawValue: rawValue - 1) }

    /// Steps the user may pass without giving any data.
    public var skipTitle: String? {
        switch self {
        case .medicalHistory: return "Wolę nie podawać"
        case .screening: return "Odpowiem później"
        default: return nil
        }
    }
}

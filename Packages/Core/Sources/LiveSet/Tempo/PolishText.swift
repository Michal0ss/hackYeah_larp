import Foundation

/// "1 powtórzenie", "2 powtórzenia", "5 powtórzeń".
public func repsLabel(_ count: Int) -> String {
    let word: String
    let mod10 = count % 10
    let mod100 = count % 100
    if count == 1 {
        word = "powtórzenie"
    } else if (2...4).contains(mod10), !(12...14).contains(mod100) {
        word = "powtórzenia"
    } else {
        word = "powtórzeń"
    }
    return "\(count) \(word)"
}

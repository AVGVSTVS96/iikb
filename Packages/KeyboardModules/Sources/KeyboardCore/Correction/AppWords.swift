/// Words you kept in one app, each count a level above the same count across apps (`LanguageModel`).
public struct AppWords: Codable, Hashable, Sendable {
    private(set) var counts: [String: Int] = [:]
    private(set) var following: [String: [String: Int]] = [:]
    private(set) var total = 0

    public init() {}

    mutating func record(_ word: String, after previous: String?) {
        counts[word, default: 0] += 1
        total += 1
        if let previous { following[previous, default: [:]][word, default: 0] += 1 }
        if counts.count > TypingMemory.capacity {
            counts = counts.filter { $0.value > 1 }
            total = counts.values.reduce(0, +)
            following = following.compactMapValues {
                let next = $0.filter { $0.value > 1 }
                return next.isEmpty ? nil : next
            }
        }
    }

    mutating func forget(_ word: String, after previous: String?) {
        guard let count = counts[word] else { return }
        counts[word] = count > 1 ? count - 1 : nil
        total -= 1
        if let previous, let count = following[previous]?[word] {
            following[previous]?[word] = count > 1 ? count - 1 : nil
        }
    }

    func count(of word: String) -> (count: Int, total: Int, types: Int) {
        (Self.count(of: word, in: counts), total, counts.count)
    }

    func count(of word: String, after previous: String) -> (count: Int, total: Int, types: Int) {
        guard let next = following[previous] else { return (0, 0, 0) }
        return (Self.count(of: word, in: next), next.values.reduce(0, +), next.count)
    }

    private static func count(of word: String, in counts: [String: Int]) -> Int {
        let capitalized =
            word.first?.isLowercase == true ? counts[word.prefix(1).uppercased() + word.dropFirst(), default: 0] : 0
        return counts[word, default: 0] + capitalized
    }
}

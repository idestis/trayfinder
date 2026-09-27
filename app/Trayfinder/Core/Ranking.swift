import Foundation

/// Fuzzy scoring: substring beats subsequence, word starts get a bonus. nil means no match.
nonisolated enum Fuzzy {
  static func score(_ haystack: String, _ query: String) -> Int? {
    let hayLower = haystack.lowercased()
    let qLower = query.lowercased()
    guard !qLower.isEmpty else { return 0 }
    let hay = Array(hayLower)
    let q = Array(qLower)

    if let range = hayLower.range(of: qLower) {
      let idx = hayLower.distance(from: hayLower.startIndex, to: range.lowerBound)
      var s = 100 - min(idx, 60)
      if idx == 0 || !hay[idx - 1].isLetter { s += 30 }
      return s
    }

    var j = 0
    var gaps = 0
    var last = -1
    for (k, c) in hay.enumerated() where j < q.count && c == q[j] {
      if last >= 0 { gaps += k - last - 1 }
      last = k
      j += 1
    }
    return j == q.count ? 40 - min(gaps, 35) : nil
  }
}

/// Usage score with exponential decay (14-day half-life).
nonisolated struct Frecency: Codable, Equatable, Sendable {
  static let halfLife: TimeInterval = 14 * 24 * 3600

  var score: Double
  var at: TimeInterval

  func value(now: Date) -> Double { score * pow(0.5, (now.timeIntervalSince1970 - at) / Self.halfLife) }

  func bumped(now: Date) -> Frecency { Frecency(score: value(now: now) + 1, at: now.timeIntervalSince1970) }
}

nonisolated enum Ranker {
  /// Empty query: favourites, then most used, then menu bar order. Otherwise fuzzy score plus usage and
  /// favourite boosts.
  static func rank(
    _ items: [MenuBarItem], query: String, usage: [String: Frecency], favourites: Set<String> = [],
    now: Date = Date()
  ) -> [MenuBarItem] {
    let q = query.trimmingCharacters(in: .whitespaces)
    func use(_ item: MenuBarItem) -> Double { usage[item.id]?.value(now: now) ?? 0 }

    if q.isEmpty {
      return items.enumerated()
        .sorted { a, b in
          let fa = favourites.contains(a.element.id)
          let fb = favourites.contains(b.element.id)
          if fa != fb { return fa }
          let ua = use(a.element)
          let ub = use(b.element)
          return ua != ub ? ua > ub : a.offset < b.offset
        }
        .map(\.element)
    }
    return
      items
      .compactMap { item -> (MenuBarItem, Double)? in
        guard let s = Fuzzy.score(item.haystack, q) else { return nil }
        let favourite: Double = favourites.contains(item.id) ? 25 : 0
        return (item, Double(s) + min(use(item), 20) * 3 + favourite)
      }
      .sorted { $0.1 > $1.1 }
      .map(\.0)
  }
}

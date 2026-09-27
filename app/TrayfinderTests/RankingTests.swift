import ApplicationServices
import Foundation
import Testing

private func item(_ name: String, app: String? = nil, x: CGFloat = 0) -> MenuBarItem {
  MenuBarItem(
    id: app ?? name, name: name, appName: app ?? name, bundleID: nil, pid: 1,
    frame: CGRect(x: x, y: 0, width: 24, height: 24), element: AXUIElementCreateApplication(1))
}

struct FuzzyTests {
  @Test func substringBeatsSubsequence() throws {
    let sub = try #require(Fuzzy.score("Tailscale", "tail"))
    let seq = try #require(Fuzzy.score("Tailscale", "tlsc"))
    #expect(sub > seq)
  }

  @Test func wordStartGetsBonus() throws {
    let start = try #require(Fuzzy.score("Docker Desktop", "desk"))
    let middle = try #require(Fuzzy.score("Docker Desktop", "ktop"))
    #expect(start > middle)
  }

  @Test func caseInsensitive() { #expect(Fuzzy.score("1Password", "PASS") != nil) }

  @Test func noMatch() { #expect(Fuzzy.score("Rectangle", "xyz") == nil) }

  @Test func emptyQueryMatches() { #expect(Fuzzy.score("Anything", "") == 0) }
}

struct FrecencyTests {
  @Test func halvesAfterHalfLife() {
    let now = Date()
    let f = Frecency(score: 4, at: now.timeIntervalSince1970)
    let later = now.addingTimeInterval(Frecency.halfLife)
    #expect(abs(f.value(now: later) - 2) < 0.0001)
  }

  @Test func bumpAddsOne() {
    let now = Date()
    let f = Frecency(score: 2, at: now.timeIntervalSince1970).bumped(now: now)
    #expect(abs(f.value(now: now) - 3) < 0.0001)
  }
}

struct RankerTests {
  @Test func emptyQueryOrdersByUseThenPosition() {
    let items = [item("A", x: 300), item("B", x: 200), item("C", x: 100)]
    let now = Date()
    let usage = ["C": Frecency(score: 5, at: now.timeIntervalSince1970)]
    #expect(Ranker.rank(items, query: "", usage: usage, now: now).map(\.name) == ["C", "A", "B"])
  }

  @Test func queryFiltersAndUsageBreaksTies() {
    let items = [item("Tailscale"), item("Telegram"), item("Rectangle")]
    let now = Date()
    let usage = ["Telegram": Frecency(score: 10, at: now.timeIntervalSince1970)]
    let ranked = Ranker.rank(items, query: "t", usage: usage, now: now).map(\.name)
    #expect(ranked.first == "Telegram")
    #expect(ranked.contains("Rectangle"))  // "t" is in "Rectangle" too
  }

  @Test func favouritesComeFirst() {
    let items = [item("A", x: 300), item("B", x: 200), item("C", x: 100)]
    let now = Date()
    let usage = ["A": Frecency(score: 9, at: now.timeIntervalSince1970)]
    #expect(Ranker.rank(items, query: "", usage: usage, favourites: ["C"], now: now).map(\.name) == ["C", "A", "B"])
  }

  @Test func favouriteWinsCloseMatch() {
    let items = [item("Tailscale"), item("Telegram")]
    #expect(Ranker.rank(items, query: "t", usage: [:], favourites: ["Telegram"]).first?.name == "Telegram")
  }

  @Test func matchesAppNameWhenTitleDiffers() {
    let items = [item("No alerts in your regions", app: "Air Alert")]
    #expect(Ranker.rank(items, query: "air", usage: [:]).count == 1)
  }
}

struct MenuBarItemTests {
  @Test func rowShowsAppThenItemText() {
    let status = item("3 unread chats", app: "Chat")
    #expect(status.title == "Chat")
    #expect(status.subtitle == "3 unread chats")
    #expect(item("Chat").subtitle == nil)
  }

  @Test func idIgnoresChangingTitles() {
    #expect(MenuBarItem.makeID(bundleID: "com.a", appName: "A", identifier: nil, index: 0, count: 1) == "com.a")
    #expect(MenuBarItem.makeID(bundleID: "com.a", appName: "A", identifier: nil, index: 1, count: 2) == "com.a|1")
    #expect(MenuBarItem.makeID(bundleID: nil, appName: "A", identifier: "clock", index: 0, count: 2) == "A|clock")
  }
}

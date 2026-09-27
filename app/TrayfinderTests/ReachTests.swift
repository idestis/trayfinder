import CoreGraphics
import Testing

struct ReachTests {
  @Test func offScreenIsOverflow() {
    #expect(Reach.of(CGRect(x: -1, y: 0, width: 72, height: 24), notch: nil) == .overflow)
    #expect(Reach.of(CGRect(x: 100, y: 0, width: 0, height: 24), notch: nil) == .overflow)
  }

  @Test func underTheNotch() {
    let notch: ClosedRange<CGFloat> = 660...850
    #expect(Reach.of(CGRect(x: 700, y: 0, width: 30, height: 24), notch: notch) == .notch)
    #expect(Reach.of(CGRect(x: 845, y: 0, width: 30, height: 24), notch: notch) == .notch)  // partly covered
    #expect(Reach.of(CGRect(x: 900, y: 0, width: 30, height: 24), notch: notch) == .visible)
  }

  @Test func onScreenIsVisible() {
    #expect(Reach.of(CGRect(x: 2400, y: 0, width: 36, height: 24), notch: nil) == .visible)
  }
}

# CLAUDE.md

Trayfinder: a macOS menu bar utility for finding and reaching tray icons from the keyboard. Click the mark or press ⌃⌥T: a dropdown under the mark lists icons out of sight (behind macOS's « overflow arrow or under the notch), most used first; typing filters every icon; ↵ opens the real menu, reaching it wherever it is. Favourites (⌘P) are ⌘-dragged next to the mark, which stays the rightmost app icon. It doesn't hide icons itself: macOS 27 draws the menu bar as one window, so the old stretched-separator trick can't work; Apple's overflow arrow and System Settings › Menu Bar do that job. **This repo is public.**

## Commands

Always through `task` from the repo root; if a command is missing, add it to the right Taskfile.

- `task run`: build Debug and launch "Trayfinder Dev" (own bundle id, own prefs)
- `task verify`: the gate (format check, build, tests, landing check). Must pass before a change is done.
- `task fmt`: swift-format (2 spaces, 120 columns)
- `task app:logs`: stream os.Logger output
- `task landing:dev`: serve the landing page on :4321

Don't launch the app, open the dropdown or move menu bar icons on the owner's screen unless asked; it rearranges their real menu bar.

## Layout

```
app/project.yml        XcodeGen spec (the .xcodeproj is generated, never committed)
app/Config/            xcconfigs: Version, Sparkle public key, optional gitignored Signing
app/Trayfinder/App     entry point, AppDelegate wiring, Carbon hotkeys, login item, Sparkle
app/Trayfinder/Core    pure logic, no AppKit/SwiftUI: AX scanning, Reach (visible/overflow/notch), fuzzy + frecency ranking, Shortcut
app/Trayfinder/Bar     the mark (BarController), TrayModel (scan, reach, favourites, move-and-return), ⌘-drag ItemMover
app/Trayfinder/Palette dropdown under the mark: non-activating NSPanel + SwiftUI; keys go through PaletteModel.handle
app/Trayfinder/Settings glass keyboard panel (j k choose, ↵ change, h back; Favourites list, About); SettingsModel.handle owns every key
app/TrayfinderTests    Swift Testing, not hosted: compiles Core, Support and Preferences directly
landing/               static GitHub Pages site (no build, no third-party requests) + appcast.xml
```

## Rules

- **No secrets or personal data in the repo.** Team ID lives in `.env` / `app/Config/Signing.xcconfig` (both gitignored); notary password and Sparkle private key live in the keychain. Only the Sparkle *public* key is committed.
- **Local first.** The only network code is Sparkle checking `landing/appcast.xml` on GitHub Pages. No analytics, no telemetry, no other requests. `Links` only hands URLs to the browser.
- **Efficient.** No polling timers while idle: rescans happen on palette open, app launch/quit and screen change. Anything that polls (menu-open watch, permission check) runs only while needed. Release SwiftUI trees for hidden windows.
- AX calls block; keep them off the main thread (`MenuBarScanner` is `nonisolated`). AXPress can block while a menu tracks: fire and forget.
- Swift 6, default MainActor isolation; mark pure types `nonisolated`. `Log.make`, never `print`.
- New logic goes in `Core/` with a test. No new Swift packages without asking (Sparkle is the only one).
- Glass panels only (`glassPanel`), no standard windows. Every setting reachable by keyboard; no option for what isn't built.
- Never fake hiding (stretched invisible items, captured icon images). Move an icon only for a favourite or to reach one, and put it back.
- UI copy: sentence case, no exclamation marks, verbs on buttons, works keyboard-only, light and dark.
- Changes go through PRs to `main` (required checks: `app`, `landing`, `title`; squash merge, PR title = commit). PR titles are Conventional Commits (`feat(palette): …`, `fix(bar): …`): git-cliff builds CHANGELOG and Sparkle notes from them. Labels are automatic.
- Releases: the owner runs `task release` locally (keychain holds the Developer ID cert, notary password and Sparkle key; no secrets on GitHub). It commits the version bump to `main`, tags `vX.Y.Z` and attaches `Trayfinder.dmg` to the GitHub Release.

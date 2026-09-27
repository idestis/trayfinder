# Trayfinder

A small macOS menu bar utility. It finds any menu bar icon from the keyboard and gets you to it, even when macOS has put it out of sight.

- **Search.** Click the mark or press ⌃⌥T. A dropdown lists the icons that are out of sight, most used first; type to find any icon, press ↵, and its real menu opens.
- **Reach hidden icons.** Behind macOS's « overflow arrow, Trayfinder expands the arrow and opens the icon in place. Under the notch, it moves the icon next to its mark, opens it, and puts it back afterwards.
- **Favourites.** ⌘P (or Settings › Favourites) places an icon right next to Trayfinder, which stays the rightmost app icon. macOS hides icons from the left first, so favourites stay in sight, and they rank first in search.
- **Learns what you use.** Results are ranked by how often and how recently you open them.
- **Local first.** No account, no analytics. The only network request is the optional update check.

### macOS 27

macOS 27 draws the menu bar as a single window, so the tricks older menu bar managers used to hide icons no longer work. Apple added its own « overflow arrow and per-app toggles in System Settings › Menu Bar. Trayfinder works with those instead of against them: it doesn't hide icons itself; it gets you to any icon, wherever macOS put it.

Free and open source under the [MIT licence](LICENSE). macOS 14 or later. Landing page: <https://idestis.github.io/trayfinder/>.

## Permissions

Trayfinder needs **Accessibility**. It uses it to read the names and positions of menu bar items, open their menus, and ⌘-drag an icon when you make it a favourite or when it has to reach one under the notch. It doesn't read anything else.

## Develop

Needs Xcode 26 or later and `brew install go-task xcodegen create-dmg git-cliff gh`.

```sh
task run        # build Debug and launch "Trayfinder Dev"
task verify     # format check, build, tests, landing check
task --list     # everything else
```

`app/Trayfinder.xcodeproj` is generated from `app/project.yml`; edit that, never the project. Builds are ad-hoc signed by default. To keep the Accessibility permission across rebuilds, put your `TEAM_ID` in `.env` (see `.env.example`) and run `task app:signing:setup`.

## Releasing

Releases are notarized DMGs on GitHub Releases. Sparkle reads the appcast from GitHub Pages (`landing/appcast.xml`). One-time setup:

1. A Developer ID Application certificate in your login keychain, and `TEAM_ID` in `.env`.
2. `task app:notary:setup`: stores notarization credentials in the keychain.
3. `task app:sparkle:keys`: creates the EdDSA key in the keychain and writes the public key to `app/Config/Sparkle.xcconfig`. Commit that file.
4. In the repo settings, set Pages to deploy from GitHub Actions.

Then `task app:bump:preview` to see the next version, and `task release` (or `task release -- 0.2.0`).

## Support Ukraine

Trayfinder is made by a Ukrainian developer. If it saves you time, please consider donating to [United24](https://u24.gov.ua/).

## Credits

Made by [Dmytro Shamenko](https://www.linkedin.com/in/dmytroshamenko/).

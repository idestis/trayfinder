# Security

Trayfinder asks for Accessibility access, so it takes reports seriously.

Please report vulnerabilities privately through [GitHub security advisories](https://github.com/idestis/trayfinder/security/advisories/new), not in public issues. Expect a reply within a week.

What Trayfinder does with its access is described in the [README](README.md#permissions). The only network request it makes is the Sparkle update check against `https://idestis.github.io/trayfinder/appcast.xml`; updates are signed with an EdDSA key and the app is notarized by Apple.

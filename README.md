# Finlynq for iPhone, iPad and Mac

A native SwiftUI client for [Finlynq](https://github.com/finlynq/finlynq), the open-source personal finance tracker. It signs in to any Finlynq server, finlynq.com or your own, and uses the same REST API as the web app.

It covers Home, Activity, Budget, Bills, Goals, Accounts, Investments, Debts, Insights, the import review queue and Settings, including category editing. On iPhone it can also log Apple Pay purchases through a Shortcuts automation (see [Shortcuts/README.md](Shortcuts/README.md)).

Requires iOS 18 or macOS 15.

## Build

You need Xcode 27.2 or later, [XcodeGen](https://github.com/yonaskolb/XcodeGen) 2.46 or later, and [SwiftLint](https://github.com/realm/SwiftLint).

```sh
brew install xcodegen swiftlint
xcodegen generate
open Finlynq.xcodeproj
```

To sign with your own Apple developer team, create `Config/Local.xcconfig` (it is gitignored):

```
DEVELOPMENT_TEAM = <your team id>
```

Without it, the scripts sign the app ad-hoc, which is enough for the simulator and the Mac.

## Tests

```sh
OFFLINE=1 scripts/check.sh
```

This runs SwiftLint in strict mode, the unit tests, an iOS build and a UI smoke test. Without `OFFLINE=1` it also decodes live responses from the public demo account on finlynq.com. The demo is shared, so the tests only read from it.

`FINLYNQ_FIXTURES=1` runs the app on the saved responses in `Fixtures/` with no server. `scripts/screens.sh` screenshots screens in fixture mode next to their designs in `docs/design/`.

## Layout

- `Finlynq/API`: the REST client and models. `docs/api-reference.md` lists every endpoint the app calls.
- `Finlynq/Features`: one folder per screen.
- `Finlynq/Design`: colors, icons, charts and the width classes that pick a layout.
- `docs/design`: the approved designs as HTML boards, one per screen and device.

## License

AGPL-3.0, the same license as Finlynq. See [LICENSE](LICENSE).

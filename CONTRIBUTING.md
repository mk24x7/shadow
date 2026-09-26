# Contributing to Shadow

Thanks for helping. Shadow explains PATH; it must never change it. Accuracy of what it reports matters more than the number of things it detects. Please read this before opening a pull request.

## Requirements

- macOS 13 or later
- Xcode 15 or later (Swift 5.9 or later)

## Build

```sh
swift build                    # debug build of the library, CLI and app
swift run shadow node python3  # run the CLI from source
./build.sh                     # release build: dist/Shadow.app and dist/shadow
```

The app target is called `ShadowApp` and the CLI target `shadow`, because macOS volumes are case-insensitive and `Shadow` and `shadow` would collide. `build.sh` names the app binary `Shadow` inside the bundle.

## Test

```sh
swift test
scripts/check-ascii.sh
shellcheck build.sh dmg.sh package.sh scripts/*.sh
```

CI runs the same commands. Tests build fake PATH trees under a temporary directory with small shell scripts that print a version, so they never depend on what is installed on the machine running them.

## Where things live

| File | What it does |
| --- | --- |
| `Sources/ShadowCore/PathResolver.swift` | Splits PATH and finds every executable copy in order |
| `Sources/ShadowCore/ManagerDetector.swift` | Labels a copy with its manager and decides whether it is a shim |
| `Sources/ShadowCore/VersionProbe.swift` | Runs the version command and parses the output |
| `Sources/ShadowCore/ShellCapture.swift` | Captures PATH from each shell context |
| `Sources/ShadowCore/RcExplainer.swift` | Finds the rc-file line that added a directory |
| `Sources/ShadowCore/VersionFiles.swift` | Finds `.nvmrc`, `.tool-versions` and friends |
| `Sources/ShadowCore/Findings.swift` | The rules that produce findings |
| `Sources/ShadowCore/Analyzer.swift` | Ties everything together into a `Report` |

## Adding a manager

1. Add a `Manager` constant in `Models.swift` with the right `kind` (`versionManager` for tools that switch versions of one language).
2. Teach `ManagerDetector` its shim directory (if any) and its install directories.
3. If it has an init line (`eval "$(x init)"`), add it to `RcExplainer.initLineManager`.
4. If it reads version files, add it to `VersionFiles.readers`.
5. Add tests that build its layout in a `Fixture` and assert the classification.
6. Add a line under `## [Unreleased]` in `CHANGELOG.md` and update the README table.

## Commit messages

- Imperative mood, capitalised, no trailing period: "Detect proto shims", not "added proto".
- Subject line of 72 characters or fewer, blank line, then a body explaining why when it is not obvious.
- No emojis or decorative symbols anywhere: commits, code, comments or documentation. Every file must be pure ASCII.

## Pull requests

- Keep each pull request focused on one change.
- Include tests for bug fixes and new behaviour.
- Never add code that writes to rc files, PATH, or anything outside Shadow's own output.

# Contributing

Use [issues](https://github.com/jasonwong2001/palpebra/issues) for reproducible bugs and focused feature proposals, and pull requests for changes. The [roadmap](docs/ROADMAP.md) lists ideas already noted. Please follow the [Code of Conduct](CODE_OF_CONDUCT.md), and report vulnerabilities privately through the [security policy](SECURITY.md).

## Prerequisites

Development requires a Mac running macOS 13 or later, Xcode or Command Line Tools, and **Swift 6.2 or later** with its bundled `swift format`. All targets use Swift 6 language mode; the app has no third-party dependencies and needs no network access to build or test. Run commands from the repository root.

CI requires Swift 6.2 or later and prints the selected Swift and formatter versions. Use the same toolchain locally for consistent `swift format` output.

## Checks

```sh
swift --version
swift format --version
swift format lint --strict --recursive Sources Tests
./scripts/check-build-flags.sh
swift build -c release
./scripts/test.sh
CONFIG=release ./scripts/make-app.sh
ditto -c -k --keepParent build/Palpebra.app build/Palpebra.zip
```

These match [CI](.github/workflows/ci.yml), in workflow order. CI runs on `main` pushes and all pull requests, then uploads the zipped app as a 14-day artifact. The zip preserves the signed bundle and executable permissions. Release bundles are universal (arm64 + x86_64), ad-hoc signed with hardened runtime, and not notarized. `GITHUB_RUN_NUMBER` supplies the CI build number; local builds use the git commit count unless overridden. See [Releasing](docs/RELEASING.md) for metadata, snapshot archives and the owner-run release process.

For ordinary development, build DEBUG and format changed Swift before rerunning strict lint:

```sh
swift build
swift format --in-place --recursive Sources Tests
```

After documentation changes, check relative links, heading anchors and HTML image paths offline. This check requires Python 3.9 or newer and no additional packages; external URLs are reported as skipped:

```sh
python3 scripts/check-doc-links.py
```

The [test wrapper](scripts/test.sh) forwards extra arguments to SwiftPM. A CLT-only installation can ship Swift Testing without the normal module search path, and can omit its Foundation cross-import overlay. The wrapper adds the installed framework search/rpath flags, the rpath for Swift Testing's interop library where newer releases ship it separately, and disables that missing overlay when necessary. Use the wrapper rather than invoking `swift test` directly; no dependency or framework download is needed.

The packaging flags check exercises the same parser as `make-app.sh`, including unset/empty flags, multiple flags, quoted spaces, whitespace-only input and explicit empty arguments. It runs no SwiftPM commands.

Sandboxed agents must add `--disable-sandbox` to every SwiftPM invocation, including `swift build` and the test wrapper, and prefix bundling/archive commands with `SWIFT_BUILD_FLAGS=--disable-sandbox`. For example:

```sh
swift build --disable-sandbox
./scripts/test.sh --disable-sandbox
SWIFT_BUILD_FLAGS=--disable-sandbox ./scripts/make-app.sh
```

Both [CI](.github/workflows/ci.yml) and [release](.github/workflows/release.yml) use `macos-15` and select the newest installed non-beta `/Applications/Xcode_26*.app` by version, exporting `DEVELOPER_DIR` through `GITHUB_ENV`. Every job requires Swift 6.2 or newer and prints Swift and formatter versions. If no matching Xcode exists, the error lists installed bundles and suggests `macos-26` or a different path. After runner or Xcode updates, confirm the selected Swift minor and available action major versions, or pin reviewed action SHAs. Dependabot checks GitHub Actions weekly. CI has read-only contents permissions and cancels superseded runs for the same ref; the [draft-release workflow](.github/workflows/release.yml) separately has contents-write permission.

## Rules

[Architecture](docs/ARCHITECTURE.md) describes the module boundaries and stored formats.

- Keep `PalpebraCore` Foundation-only. Supply dates, calendars, signals and file/defaults locations explicitly; keep macOS adapters and UI in the app target.
- Add no third-party dependencies or networking code. Keep all UI text English-only, with no localization helper or `Locale.preferredLanguages`. Source-policy tests enforce these decisions.
- Start logic bug fixes with a failing Core regression test whenever the logic lives in, or can move to, Core. Test behavior and boundary cases rather than duplicating the implementation.
- Change persisted defaults keys, paths, JSON fields or enum raw values only with an explicit migration and test. Keep additive decoding and legacy data recovery intact.
- Tests and development tools must use temporary directories and `UserDefaults(suiteName:)`; never read or modify real user data. Use the isolated DEBUG hooks below for UI checks.
- Use only original artwork for the icon/logo; SF Symbols are allowed in ordinary UI. Follow the [icon regeneration guide](docs/RELEASING.md#regenerate-the-icon) when changing the icon.
- Keep every commit buildable and passing tests, packaging-parser checks and lint. Use small Conventional Commits, for example `fix(engine): preserve cooldown after ignored rest`.
- Non-interactive agents never launch the GUI. Offscreen preview rendering is a separate, explicit DEBUG path. Agents must not push, create repositories/releases/tags, or handle signing credentials; release publication belongs to the owner.

## DEBUG tools

Build the DEBUG binary with `swift build`. All three hooks below choose a unique temporary data directory and throwaway defaults suite before constructing stores. History, onboarding, settings and custom images stay isolated. Normal exit cleans them up; a forced kill can leave only disposable temporary files. These sessions skip notification authorization and login-item mutations. Bare binaries and hooked bundles cannot deliver system notifications; permission/login-item QA needs an ordinary installed bundle without hooks.

### Offscreen documentation previews

```sh
.build/debug/Palpebra --render-previews docs/images
```

This path does not start the app event loop or show windows. AppKit still needs a usable macOS window-server session; if capture cannot work in your environment, render in an interactive macOS session instead. Creation or write failures are logged, printed to stderr, and exit with status 1.

The renderer uses explicit Aqua/Dark Aqua appearance, the matching SwiftUI color scheme, and an opaque `windowBackgroundColor` behind the views. It writes two pixels per point, so the README stays sharp on Retina displays, with these names (the full-screen previews are JPEG because their dithered gradient compresses poorly as PNG):

| View | Light | Dark |
| --- | --- | --- |
| Today | `today-light.png` | `today-dark.png` |
| Dock tile at 0, 45, 85 and 100% | `dock-light.png` | `dock-dark.png` |
| Full-screen rest | `overlay-fullscreen-light.jpg` | `overlay-fullscreen-dark.jpg` |
| Mini reminder | `mini-reminder-light.png` | `mini-reminder-dark.png` |
| Analysis | `analysis-light.png` | `analysis-dark.png` |
| Detection | `detection-light.png` | `detection-dark.png` |
| Rules | `rules-light.png` | `rules-dark.png` |
| Settings | `settings-light.png` | `settings-dark.png` |

The [README](README.md#screenshots) selects variants with `<picture>` and `prefers-color-scheme`. Check the images visually, confirm that every pixel is opaque, and keep each file under about 300 KB before committing. The Rules and Settings previews also cover form help text and wrapping. Sample dates follow the rendering date, so regenerating can change chart labels. The owner may substitute real screenshots with the same names. No real settings/history are read; only the requested output images persist.

### Interactive main window and self-test

Run these only in an interactive macOS session:

```sh
PALPEBRA_OPEN_MAIN=1 .build/debug/Palpebra
PALPEBRA_SELFTEST=1 .build/debug/Palpebra
```

Open-main seeds sample history spanning weeks, months and years. Inspect Analysis's All time range, weekly/monthly buckets and compliance. Settings' image/data actions operate only on temporary samples, but CSV export still writes wherever you choose. Use temporary destinations. DEBUG adds Pause 1 min and Pause 2 min to check automatic expiry without waiting half an hour.

The self-test starts a full-screen rest and exits after checking overlay visibility, running state and key window. It displays an overlay. CI runs it in a separate nonblocking GUI job with a ten-minute job timeout and a one-minute launch timeout. To reproduce the bundle path interactively:

```sh
CONFIG=debug ./scripts/make-app.sh
PALPEBRA_SELFTEST=1 build/Palpebra.app/Contents/MacOS/Palpebra
```

All hooks, the renderer and short pause options are excluded from release builds. Verify after building release:

```sh
strings .build/release/Palpebra | rg 'PALPEBRA_SELFTEST|PALPEBRA_OPEN_MAIN|--render-previews|Pause [12] min'
```

Expect no matches (exit status 1). File-operation logs use the bundle identifier as their subsystem, or `Palpebra` for a bare binary. User-initiated export, image and history-clear failures also show an alert.

## Manual UI checks

Use isolated open-main for data/image/keyboard checks. Verify both light and dark appearance and macOS 13 plus a newer system where available. Before a release, repeat system integration checks on an ordinary installed bundle.

- Full-screen rest covers all existing displays over full-screen apps and other Spaces, fades in, opens on its full time (2:00 for a two-minute break) and fades out when it ends; mini stays visible and has no close/Command-W bypass. Check free, challenge and Cannot skip modes. Wrong puzzle answers change the puzzle. Quit is disabled during a Cannot skip popup (a notification break keeps it); hold Esc for five seconds to exit a focused popup. Release or focus loss cancels that hold. Verify the emergency outcome and that Quit works afterwards.
- Mini/notification: continued work ends as ignored, walking away completes after real rest, and lock/sleep reconciles on return. While you rest, the mini card counts down every second; while you work it holds. The next reminder waits from the previous session's actual end. Try Always on and the video option, whose coarse display-sleep assertion may also come from keep-awake tools.
- Record a global shortcut, use it from another app, and check a conflict produces an error. Check pause expiry, the Dock ring/toggle, daily screen-time notices and About's version/build.
- Deny/restore notifications and verify Rules refreshes its warning on return. Notification-style Rest now cannot complete when denied. Toggle Open at login and change it in System Settings; the app must show the actual status, approval guidance or registration error. These need a normal bundle without DEBUG hooks.
- Cancel and confirm history deletion; export CSV; force a write failure with a temporary unwritable destination and verify its alert. Adopt/remove a temporary custom image and check thumbnail/popup refresh.
- Check week/month grouping, cross-year ordering and labels, each chart's daily average, completed-only compliance and the nine CSV columns. Close and reopen the main window: it returns at the same size, position and tab. Type values into the number fields (for example a 7-minute reminder or a 20-second break), including ones outside the range in the tooltip, and check they're clamped, kept after relaunch, and stepped by the arrows.

With VoiceOver, inspect Today's fatigue percentage and in-use/resting state, each Analysis bar's date and duration, compliance percentage/outcome counts, and both popup counters as minutes/seconds. The mini hint should explain that activity can increase its remaining time.

With keyboard navigation, Tab and Shift-Tab through rest controls and activate buttons with Space. Skip has initial focus; Command-S skips a free break or opens the challenge. Return submits the focused answer field; Esc cancels back to resting and returns focus to Skip. Recheck Cannot skip/hold-Esc with VoiceOver on and off. In the main window, check Command-C/V/X/A/Z, Shift-Command-Z, Command-W/M and Settings (Command-comma).

The owner also checks downloaded-zip installation on a second macOS account, native Apple silicon and Intel (or Rosetta) launch, and the background timer measurement below. Automated checks do not replace those runs.

## One-hour background timer measurement (owner-run)

Run this in an interactive macOS session. Quit any other Palpebra instance and build DEBUG as above. Start unified-log capture in a separate terminal before launching the app:

```sh
log stream --style compact --level debug --predicate 'process == "Palpebra" AND category == "Timing"' | tee /tmp/palpebra-timing.log
```

Then launch the isolated open-main session shown above. In Rules, choose Notification reminders so no popup opens during measurement. Bare development binaries cannot deliver notifications; this still exercises the timer without requesting permissions. Close the main window with Command-W, dismiss the status menu, and leave all Palpebra windows closed for at least one hour. Keep the Mac awake with its display on while using other apps normally. Avoid opening Palpebra windows/menus, attaching a debugger or adding a keep-awake power assertion.

DEBUG's `Timing` category reports `interval_seconds` for the five-second periodic timer, using monotonic system uptime. Observer/deadline/emergency checks do not reset that measurement. `locked` and `asleep` show system state. The timer has one second of tolerance, so expect intervals of five to six seconds (roughly 600 to 720 samples/hour); investigate gaps over 30 seconds while awake. Note lock, display/system sleep, wake and heavy CPU-load periods before attributing gaps to App Nap.

After the hour, stop capture with Control-C and quit normally. Record macOS/toolchain versions, Show Palpebra in the Dock, capture duration, sample count and largest awake interval with the log file. If gaps over 30 seconds repeat, review that evidence before adding a scoped `beginActivity` assertion to engine start/stop. No such assertion is currently used. Release builds omit the timing instrumentation.

## PR checklist

- [ ] Explain the problem and resulting behavior, with an issue or reproduction when relevant.
- [ ] Keep the change focused and follow the rules above.
- [ ] Add/observe a failing regression before a logic fix; update migrations if stored formats change.
- [ ] Pass build, tests, packaging flags check, strict lint and app bundling from Checks.
- [ ] Describe manual checks performed and any checks still needed; include UI images when useful.
- [ ] Update user-facing docs and the changelog for behavior changes.
- [ ] Confirm tests/dev tools use disposable data and no credentials or private usage records are included.

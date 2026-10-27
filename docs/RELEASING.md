# Releasing Palpebra

Packaging requires macOS, Swift 6.2 or later from Xcode or Command Line Tools, and Apple's bundled `lipo`, `codesign`, `ditto`, `sips` and `iconutil` tools. Local packaging needs no dependencies or network access. The GitHub draft-release step needs network access and GitHub CLI (`gh`). Run the commands below from the repository root. Packaging never launches the app.

CI and release workflows require Swift 6.2 or later and print the selected Swift and formatter versions. Use the same toolchain locally for consistent `swift format` output.

Both workflows use `macos-15`, select the newest installed non-beta `/Applications/Xcode_26*.app` by version, and export `DEVELOPER_DIR` through `GITHUB_ENV`. If no matching bundle is installed, the error lists installed Xcodes and suggests `runs-on: macos-26` or a different Xcode path.

The current distribution is **ad-hoc signed with hardened runtime and is not notarized**. It does not require a paid Apple Developer account or signing credentials. macOS may block a downloaded build until the user approves it in Privacy & Security; hardened runtime alone does not establish a trusted developer identity. The owner must complete the first-launch and native/Rosetta checks before publishing.

## Version and bundle metadata

[VERSION](../VERSION) is the only source of the app version. Use a numeric `major.minor.patch` value suitable for `CFBundleShortVersionString`. The build number is the first available of:

1. `BUILD_NUMBER`, an explicit positive integer.
2. `GITHUB_RUN_NUMBER`, when running in GitHub Actions.
3. `git rev-list --count HEAD`, for local builds from a git checkout.
4. `1`, with a printed note, when the repository root has no `.git`, as in an extracted source archive.

The bundler copies [Resources/Info.plist](../Resources/Info.plist) and replaces `__VERSION__` and `__BUILD_NUMBER__` with those values before signing. About reads both from the finished bundle. The bundle identifier is defined only in that template; settle its ownership before the first public release. Changing it after release changes the settings domain and notification identity.

## Build and inspect a bundle

```sh
./scripts/make-app.sh
plutil -lint build/Palpebra.app/Contents/Info.plist
plutil -p build/Palpebra.app/Contents/Info.plist
lipo -archs build/Palpebra.app/Contents/MacOS/Palpebra
codesign --verify --strict --verbose=2 build/Palpebra.app
codesign -dv build/Palpebra.app
```

The default `CONFIG=release` builds arm64 and x86_64 separately, combines them with `lipo`, embeds `Contents/Resources/AppIcon.icns`, and signs with `--options runtime --sign -`. Expect `x86_64 arm64` and `flags=0x10002(adhoc,runtime)`. The plist must name `AppIcon.icns` and show the version and build number above.

For owner QA, `CONFIG=debug ./scripts/make-app.sh` builds only the host architecture and retains DEBUG tools. Both configurations write `build/Palpebra.app`, replacing the previous bundle only after assembly and signature verification succeed. The release configuration excludes preview/self-test/open-main hooks and short QA pauses. See [CONTRIBUTING.md](../CONTRIBUTING.md) for isolated development sessions; agents must not launch the GUI.

`SWIFT_BUILD_FLAGS` forwards extra arguments to every SwiftPM invocation, including binary-path queries. It supports shell-style quoting without evaluating shell substitutions. In a sandbox, use:

```sh
SWIFT_BUILD_FLAGS=--disable-sandbox ./scripts/make-app.sh
CONFIG=debug SWIFT_BUILD_FLAGS=--disable-sandbox ./scripts/make-app.sh
```

## Make a review snapshot

Snapshot mode requires a clean checkout, including staged and untracked files, but does not require a tag:

```sh
./scripts/release.sh --snapshot
(cd dist && shasum -a 256 -c SHA256SUMS)
```

It creates `dist/Palpebra-<version>-snapshot-<shortsha>.zip` and `dist/SHA256SUMS`. The checksum file names the archive just produced, even if older archives remain in `dist/`. Snapshots are review artifacts, not tagged releases. In a sandbox, prefix the release command with `SWIFT_BUILD_FLAGS=--disable-sandbox`.

## Cut a public release (owner)

1. Update `VERSION`, add a matching `## [<version>] - YYYY-MM-DD` section in [CHANGELOG.md](../CHANGELOG.md), and change the `Palpebra-<version>.zip` name in the README's [download and install steps](../README.md#install). For 1.0.0, replace `RELEASE_DATE` in the prepared section with the release date. Run [CI's local checks](../CONTRIBUTING.md#checks), finish manual QA and commit every intended input. Wait for CI on the reviewed `main` commit before tagging.
2. On that exact commit, the owner creates and pushes the version tag:

   ```sh
   version="$(cat VERSION)"
   git tag -a "v$version" -m "Palpebra $version"
   git push origin "v$version"
   ```

3. The tag push starts [Draft release](../.github/workflows/release.yml) on `macos-15` with the same explicit stable Xcode 26 selection and Swift version checks as CI. It fetches the full history and tags, checks the triggering tag against `VERSION`, and runs `./scripts/release.sh` in default tagged mode. The script requires the matching tag at `HEAD` and a clean checkout, builds the universal app, ad-hoc signs with hardened runtime, and writes the zip and checksum. The CI run number becomes the bundle build number. No signing secrets are used.
4. The workflow extracts only the matching version's changelog section, stopping at the next version heading. If the section is absent or empty, the workflow emits a warning and uses explicit placeholder notes telling the owner to add release notes before publishing. It does not substitute the Unreleased section.
5. Using the workflow's GitHub token, `gh release create --draft --verify-tag` creates a **draft**, attaching `Palpebra-<version>.zip` and `SHA256SUMS`. Only people with write access can see a draft. Until it's published, everyone else finds no release: the README's download link reaches "There aren't any releases here", and the tag's page lists only GitHub's automatic **Source code** archives, which are easy to mistake for the app. Only this workflow has `contents: write`; CI remains read-only. The release workflow does not publish the release or create a missing tag. A rerun for a tag with an existing release fails rather than overwriting it; inspect the existing draft and assets before any owner cleanup.
6. Download the draft assets and verify their checksum. Extract the zip to a temporary directory, verify the app's signature and both architectures, then test native/Rosetta launches and installation on a second user account. Install there by following the README's [install steps](../README.md#install) as written, and correct them if a macOS dialog differs. Review the notes and replace any fallback text.
7. For the first release, make the repository public, enable Private vulnerability reporting under Settings → Advanced Security, and set up protection for `main`. Add the repository description and topics, and a contact method on your GitHub profile for conduct reports.
8. **Publish the release.** This is the step that makes the app downloadable. On the repository's **Releases** page, open the draft, click **Edit**, leave **Set as the latest release** selected and click **Publish release**. From a terminal, `gh release edit "v$version" --draft=false --latest` does the same.
9. Signed out, for example in a private browser window, open the README's **Download for macOS** link. It must show the new release with `Palpebra-<version>.zip` and `SHA256SUMS` under **Assets**, above the two Source code archives. Download the zip from there and check it against `SHA256SUMS`.

On the first run, and after runner or Xcode updates, check the workflow logs: the selected Xcode's Swift minor version should match local development and every action major version must be available, or pin the actions to reviewed commit SHAs. Local agents never push tags, create or publish GitHub releases, or launch the app.

For an offline check of the same packaging on a clean, already-tagged checkout:

```sh
./scripts/release.sh
(cd dist && shasum -a 256 -c SHA256SUMS)
```

Default mode refuses a dirty tree, a missing `v<VERSION>` tag, or a matching tag that points to another commit. Both modes always build the universal release configuration, regardless of an inherited `CONFIG=debug`, and check that the checkout did not change during the build. They use `ditto -c -k --keepParent` to preserve the app bundle in the zip. Build outputs in `build/`, `.build/` and `dist/` are ignored by git.

## Regenerate the icon

Run the generator **outside sandboxed environments** so Apple's `iconutil` produces the committed ICNS file:

```sh
swift scripts/make-icon.swift
```

The generator draws the original 1024×1024 [master PNG](../Resources/AppIcon.png) with CoreGraphics, using a rounded square, the popup's deep-violet colors and a closed-eyelid motif. It uses no SF Symbols, fonts or outside artwork. `sips` creates all ten standard 1×/2× representations in `build/AppIcon.iconset`; `iconutil` packages [AppIcon.icns](../Resources/AppIcon.icns) with Apple's canonical small-icon layout and metadata. Commit the generator, master PNG and ICNS together when changing the artwork. Bundling uses the committed ICNS.

The PNG-backed fallback is a **last resort for local inspection** when `iconutil` fails. AppKit can render it, but `iconutil -c iconset` misreads its `icp4`/`icp5` small-icon entries. Do not replace the committed canonical file with a sandbox-generated fallback. Regenerate outside the sandbox with `iconutil`, then check it with `iconutil -c iconset Resources/AppIcon.icns -o build/IconCheck.iconset` and inspect all ten sizes.

## If you get a Developer ID later

This is a future manual workflow, **documentation only**. The current scripts always ad-hoc sign and do not consume credentials. Before changing distribution, add a tested Developer ID signing path and temporary CI keychain provisioning, then repeat installation QA. Sign the app before making the notarization upload:

```sh
codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_APPLICATION_IDENTITY" build/Palpebra.app
codesign --verify --strict --verbose=2 build/Palpebra.app
ditto -c -k --keepParent build/Palpebra.app dist/Palpebra-notarization.zip
xcrun notarytool submit dist/Palpebra-notarization.zip --keychain-profile Palpebra-notarization --wait
xcrun stapler staple build/Palpebra.app
xcrun stapler validate build/Palpebra.app
```

After successful notarization and stapling, recreate the distribution zip from the stapled app and regenerate `SHA256SUMS`. Do not run today's bundler on that app afterwards: it replaces the bundle and ad-hoc signs it again.

CI would need repository secrets for the Developer ID certificate/private key export (`DEVELOPER_ID_CERTIFICATE_BASE64`), its import password (`DEVELOPER_ID_CERTIFICATE_PASSWORD`), the certificate identity (`DEVELOPER_ID_APPLICATION_IDENTITY`), and notarization authentication (`APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_SPECIFIC_PASSWORD`). Provision the `Palpebra-notarization` keychain profile from those credentials in a temporary keychain and delete that keychain after the job. Keep credentials out of the repository and logs; do not expose signing secrets to pull requests from forks. An App Store Connect API key can replace the Apple ID credentials if that is the owner's chosen notarization setup.

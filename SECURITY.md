# Security policy

## Supported versions

| Version | Security fixes |
| --- | --- |
| 1.0.x | Supported |
| Earlier prototypes | Unsupported; update to 1.0.x |

Please reproduce reports on the latest 1.0.x release where possible. Palpebra has no automatic update mechanism; updates are distributed through [GitHub Releases](https://github.com/jasonwong2001/palpebra/releases).

## Report a vulnerability

Use [GitHub private vulnerability reporting](https://github.com/jasonwong2001/palpebra/security/advisories/new): the **Report a vulnerability** button on the repository's Security tab. Do not disclose an unpatched vulnerability, personal usage history or exploit details in a public issue or pull request.

Include the affected Palpebra version/build, macOS version, reproduction steps, expected security impact, and any minimal sample file needed to demonstrate the problem. Redact personal data. Maintainers will acknowledge and investigate privately, coordinate a fix and disclosure with you, and credit you with your consent. This volunteer project cannot promise a fixed response or release deadline.

Palpebra works offline and keeps settings, history and a chosen background image on the Mac (see [Privacy](README.md#privacy)). Reports about malformed files or unwanted access to that data are in scope.

Published bundles are ad-hoc signed with hardened runtime and are **not notarized**. Follow the [installation instructions](README.md#install) and verify the release archive against `SHA256SUMS`.

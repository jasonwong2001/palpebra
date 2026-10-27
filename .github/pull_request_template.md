## Problem and resulting behavior

Describe the problem, the trigger, and what changes for the user. Link a related issue if applicable.

## Validation

List the checks you ran, their results, and any manual checks still needed. Include UI images where helpful.

- [ ] Build, tests, packaging flags check, strict lint and app bundle pass (see [Contributing](../CONTRIBUTING.md#checks)).
- [ ] Logic fixes begin with a failing regression where testable in Core.
- [ ] Persisted-format changes include a migration and test; otherwise stored keys/paths/raw values are preserved.
- [ ] Tests and development tools use disposable data; no credentials or private usage records are included.
- [ ] UI text remains English-only; no networking or third-party dependencies are added.
- [ ] User-facing docs and changelog reflect behavior changes.
- [ ] The change follows the [Code of Conduct](../CODE_OF_CONDUCT.md) and contributor rules.

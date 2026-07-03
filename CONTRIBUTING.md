# Contributing to LinxCGMKit-Trio

Thank you for helping improve this community Trio plugin. This project is maintained by volunteers — not Linx, Nightscout, or Trio core maintainers.

## Before you start

- Read the [README](README.md) and [INTEGRATION.md](INTEGRATION.md).
- This software is **not a medical device**. Do not claim clinical safety or accuracy in issues or PRs.
- Test on a **real device** with a Linx sensor when your change affects BLE scanning, decoding, or calibration.

## How to contribute

1. **Fork** [LinxCGMKit-Trio](https://github.com/Hristos0527/LinxCGMKit-Trio) on GitHub.
2. Create a **feature branch** from `master` (e.g. `fix/background-scan-watchdog`).
3. Make focused changes with a clear commit message.
4. Open a **Pull Request** against `master` with:
   - What changed and why
   - How you tested (device, iOS version, Trio build, sensor serial if relevant)
   - Any known limitations or follow-ups
5. Respond to review feedback promptly.

## Code style

- **Swift 5**, match existing formatting in the file you edit.
- Prefer small, readable functions over clever abstractions.
- Keep UI strings and user-facing copy in **English**.
- Follow LoopKit / Trio patterns used elsewhere in this repo (`CGMManager`, passive BLE scan, SwiftUI settings).
- Do not vendor LoopKit — assume it comes from the host Trio workspace.

## Scope

- Bug fixes and improvements to Linx CGM integration are welcome.
- Large refactors should be discussed in an issue first.
- Changes that require upstream Trio merges should note that in the PR; see [docs/UPSTREAM_PR_DRAFT.md](docs/UPSTREAM_PR_DRAFT.md) for context.

## Reporting bugs

Use the [bug report template](.github/ISSUE_TEMPLATE/bug_report.yml). Include device model, iOS version, Trio version, steps to reproduce, and relevant logs.

## Disclaimer

By contributing, you agree that your contributions are licensed under the same [AGPL-3.0](LICENSE) as the project. You must not introduce medical claims, regulatory statements, or warranty language beyond the project disclaimer.

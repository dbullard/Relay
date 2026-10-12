# Contributing to Relay

Thank you for helping Relay become a community-maintained app. Useful contributions include reproducible bug reports, hardware testing, documentation, focused fixes, and helping other users.

## Before changing code

Check existing issues. Open an issue before a substantial feature or architectural change so maintainers can discuss scope. Small, clearly explained bug fixes can go directly to a pull request.

Follow the [development setup](docs/DEVELOPMENT.md). Keep changes focused and follow nearby Swift/SwiftUI conventions. The Mobile target uses explicit source inclusion, so verify target membership when adding shared files.

## Pull requests

Describe the problem, the resulting behavior, and how you verified it. Include relevant tests for behavior changes. For UI changes, provide screenshots where useful. Mention hardware you tested and any unverified cases.

Do not commit secrets, personal logs, signing files, local configuration, proprietary runtimes, or generated build outputs. Use synthetic fixtures instead of customer captures. Hardware protocols and third-party APIs should cite publicly available documentation rather than distributing vendor manuals without permission.

Run the macOS test command in the README. Fix regressions introduced by your changes; document unrelated baseline failures rather than hiding them. Contributions are reviewed when maintainers have time; submission does not guarantee acceptance or a particular release date.

## License and maintainership

By submitting a contribution, you agree to license your contribution under this repository's MIT License and confirm that you have the right to contribute it. Preserve third-party copyright and license notices.

We welcome future maintainers. Build trust through sustained contributions, thoughtful reviews, and reliable testing. Repository administration and release-signing access are separate responsibilities and will be granted deliberately.

Be respectful and constructive. See [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).

# Release checklist

A source push is not a signed app release. There is no automatic deployment or distribution workflow in this repository.

- [ ] Mac build and full tests pass with the committed package versions.
- [ ] Test a Release build with no license, no account, and no internet: free features remain available.
- [ ] Verify Preview off/on with restart, including preserved saved DAW protocols.
- [ ] Verify Support points to this repository and contains no personal-payment prompt.
- [ ] Verify automatic crash consent and intentional manual feedback delivery using approved service configuration.
- [ ] Confirm app version/build, release notes, minimum OS, and known limitations.
- [ ] Review dependency licenses, NDI runtime packaging, and required notices.
- [ ] Sign and notarize using an authorized release identity.
- [ ] Verify the signed download on a separate Mac.
- [ ] Publish a release only after maintainers explicitly approve it; never commit credentials, signatures, or proprietary runtime binaries to source.

The old paid release's subscription wind-down and legacy server rollout are managed separately in the private legacy repository. No user data or private operational runbooks are copied here.

# Signing and notarization strategy

## Goals

- Community builds must remain installable without Apple secrets.
- Official releases should benefit from Developer ID trust when credentials are available.
- Reviewers and maintainers should understand exactly what each signing mode provides.

## Community mode (default)

Community artifacts are built in GitHub Actions with no signing secrets required.

### Build steps

1. `swift build`
2. Assemble `.app` bundle
3. Ad-hoc sign: `codesign --force --deep --sign -`
4. Verify signature: `codesign --verify --deep --strict`
5. Create DMG
6. Ad-hoc sign DMG: `codesign --force --sign -`
7. Create checksum: `shasum -a 256`

### Trust boundaries

- Ad-hoc signing does not establish developer identity.
- Gatekeeper may warn or block the app.
- Users should verify SHA-256 checksums.
- Public distribution should point users to the official GitHub repo only.

### User recovery script

`scripts/install-community-build.sh` provides a supported user-side installer that downloads the latest community DMG, copies it to `/Applications`, ad-hoc signs, removes quarantine, and launches the app.

## Trusted mode (optional)

Trusted mode is activated only when Apple Developer ID credentials are configured in CI.

### Required secrets

- `APPLE_DEVELOPER_ID_P12_BASE64`
- `APPLE_DEVELOPER_ID_P12_PASSWORD`
- `APPLE_KEYCHAIN_PASSWORD`
- `APPLE_NOTARY_KEY_ID`
- `APPLE_NOTARY_ISSUER_ID`
- `APPLE_NOTARY_PRIVATE_KEY_BASE64`

### Build steps

1. Build app bundle.
2. Import Developer ID certificate into an ephemeral keychain.
3. Sign nested code and app with `Developer ID Application`.
4. Enable hardened runtime.
5. Verify hardened runtime and signature.
6. Create DMG.
7. Sign DMG.
8. Submit DMG to `notarytool`.
9. Wait for `Accepted`.
10. Staple notarization ticket to DMG.
11. Validate with `stapler validate` and `spctl --assess`.
12. Remove temporary keychain and secrets from runner.

### CI rules

- Never log certificate material.
- Never persist keychains, certs, or notary artifacts.
- Always run cleanup via an `always()` step.
- Keep PR builds free of secret requirements.

## Fee waivers

Apple fee waivers are documented at https://developer.apple.com/help/account/membership/fee-waivers/

Qualifying entities:
- nonprofit organizations
- accredited educational institutions
- government entities

Individuals and sole proprietors are explicitly excluded.

## Do not

- Use self-signed certificates for public distribution.
- Treat Homebrew Cask as a notarization replacement.
- Describe ad-hoc signing as trusted signing.
- Store P12/base64 secrets in repository history.

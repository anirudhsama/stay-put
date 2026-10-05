#!/usr/bin/env bash
# One-time setup for .github/workflows/release.yml. Run from the repo root, authed with `gh`.
#
# Creates the "Stay Put Self-Signed" code-signing identity in the login keychain and stores it as
# SIGNING_P12_BASE64 / SIGNING_P12_PASSWORD. Every release must be signed with this same identity:
# macOS ties the Accessibility grant to it, so a new certificate makes every user re-grant access.
# It lives only in the login keychain and in the repo secrets, so back up the keychain item.
set -euo pipefail

IDENTITY="Stay Put Self-Signed"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
# LibreSSL writes a PKCS#12 `security import` accepts; OpenSSL 3 needs -legacy for the same.
OPENSSL=/usr/bin/openssl

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if security find-identity -p codesigning "$KEYCHAIN" | grep -q "\"$IDENTITY\""; then
    echo "▸ \"$IDENTITY\" already in the login keychain; leaving it and its secrets alone."
    exit 0
fi

echo "▸ Creating \"$IDENTITY\""
"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -subj "/CN=$IDENTITY" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null
P12_PASSWORD="$("$OPENSSL" rand -base64 24)"
"$OPENSSL" pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -name "$IDENTITY" -out "$WORK/signing.p12" -passout "pass:$P12_PASSWORD"
security import "$WORK/signing.p12" -k "$KEYCHAIN" -P "$P12_PASSWORD" -T /usr/bin/codesign
base64 -i "$WORK/signing.p12" | tr -d '\n' | gh secret set SIGNING_P12_BASE64
gh secret set SIGNING_P12_PASSWORD --body "$P12_PASSWORD"

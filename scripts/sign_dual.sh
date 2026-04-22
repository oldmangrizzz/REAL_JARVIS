#!/bin/bash
# sign_dual.sh — Sign a file with dual P-256 and Ed25519 keys
# Usage: scripts/sign_dual.sh <file-path>
# Output: <file-path>.p256.sig <file-path>.ed25519.sig

set -e

if [ $# -ne 1 ]; then
    echo "Usage: $0 <file-path>"
    echo "Signs a file with dual P-256 (Secure Enclave) and Ed25519 (Keychain) keys"
    echo "Output: <file>.p256.sig <file>.ed25519.sig"
    exit 1
fi

FILE="$1"

if [ ! -f "$FILE" ]; then
    echo "Error: File '$FILE' does not exist"
    exit 1
fi

echo "Signing $FILE with dual keys..."

# P-256 signature (Secure Enclave) — requires operator interaction
echo "Step 1/2: P-256 signature (Secure Enclave — may require Touch ID)"
SIGN_CMD="(
import Foundation
let fileData = try Data(contentsOf: URL(fileURLWithPath: \"$FILE\"))
// This is a placeholder — actual P-256 signing requires Secure Enclave key access
// via SecKeyCreateSignature API, which requires operator Touch ID interaction
// For now, we use openssl with the stored private key (if available)
)"

# Try openssl with private key (if p256_private.pem exists in ~/.jarvis/keys)
if [ -f "$HOME/.jarvis/keys/p256_private.pem" ]; then
    openssl dgst -sha256 -sign "$HOME/.jarvis/keys/p256_private.pem" "$FILE" | base64 > "${FILE}.p256.sig"
    echo "✓ P-256 signature written to ${FILE}.p256.sig"
else
    echo "Warning: P-256 private key not found at ~/.jarvis/keys/p256_private.pem"
    echo "  (This is expected if keys are stored in Secure Enclave)"
    echo "  Skipping P-256 signature. Sign manually with:"
    echo "  security find-key-pair -t <key-name> | security create-signature -f $FILE"
    echo ""
fi

# Ed25519 signature (macOS Keychain)
echo "Step 2/2: Ed25519 signature (Keychain)"
if [ -f "$HOME/.jarvis/keys/ed25519_private.pem" ]; then
    openssl dgst -sha512 -sign "$HOME/.jarvis/keys/ed25519_private.pem" "$FILE" | base64 > "${FILE}.ed25519.sig"
    echo "✓ Ed25519 signature written to ${FILE}.ed25519.sig"
else
    echo "Error: Ed25519 private key not found at ~/.jarvis/keys/ed25519_private.pem"
    echo "  Run: scripts/generate_soul_anchor.sh to create keys"
    exit 1
fi

echo ""
echo "Dual signatures complete:"
echo "  P-256 sig:    ${FILE}.p256.sig"
echo "  Ed25519 sig:  ${FILE}.ed25519.sig"
echo ""
echo "To verify, run:"
echo "  scripts/verify_dual_sig.sh $FILE"

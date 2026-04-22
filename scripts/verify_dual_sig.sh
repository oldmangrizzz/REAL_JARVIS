#!/bin/bash
# verify_dual_sig.sh — Verify dual P-256 and Ed25519 signatures on a file
# Usage: scripts/verify_dual_sig.sh <file-path>
# Checks: <file-path>.p256.sig <file-path>.ed25519.sig

set -e

if [ $# -ne 1 ]; then
    echo "Usage: $0 <file-path>"
    echo "Verifies dual P-256 and Ed25519 signatures"
    echo "Expected files: <file>.p256.sig <file>.ed25519.sig"
    exit 1
fi

FILE="$1"
P256_SIG="${FILE}.p256.sig"
ED25519_SIG="${FILE}.ed25519.sig"

if [ ! -f "$FILE" ]; then
    echo "Error: File '$FILE' does not exist"
    exit 1
fi

# Helper: extract public key fingerprint from canonical docs
get_pubkey_fingerprint() {
    local key_type=$1
    local pubkey_file=$2
    
    if [ ! -f "$pubkey_file" ]; then
        echo "Error: Public key file '$pubkey_file' not found"
        return 1
    fi
    
    # SHA-256 hash of the public key
    if [ "$key_type" = "p256" ]; then
        openssl x509 -in "$pubkey_file" -noout -pubkey | openssl dgst -sha256 | awk '{print $2}'
    else  # ed25519
        cat "$pubkey_file" | openssl dgst -sha256 | awk '{print $2}'
    fi
}

# Verify P-256 signature
echo "Verifying P-256 signature..."
if [ ! -f "$P256_SIG" ]; then
    echo "  ⚠ P-256 signature file '$P256_SIG' not found (skipping)"
else
    if [ -f "$HOME/.jarvis/keys/p256_public.pem" ]; then
        # Decode base64 signature and verify
        base64 -D < "$P256_SIG" | openssl dgst -sha256 -verify "$HOME/.jarvis/keys/p256_public.pem" -signature /dev/stdin "$FILE" > /dev/null 2>&1
        if [ $? -eq 0 ]; then
            P256_FP=$(get_pubkey_fingerprint "p256" "$HOME/.jarvis/keys/p256_public.pem")
            echo "  ✓ P-256 signature valid (key fingerprint: ${P256_FP:0:16}…)"
        else
            echo "  ✗ P-256 signature invalid"
            exit 1
        fi
    else
        echo "  ⚠ P-256 public key not found; cannot verify"
    fi
fi

# Verify Ed25519 signature
echo "Verifying Ed25519 signature..."
if [ ! -f "$ED25519_SIG" ]; then
    echo "  ✗ Ed25519 signature file '$ED25519_SIG' not found"
    exit 1
fi

if [ -f "$HOME/.jarvis/keys/ed25519_public.pem" ]; then
    # Decode base64 signature and verify
    base64 -D < "$ED25519_SIG" | openssl dgst -sha512 -verify "$HOME/.jarvis/keys/ed25519_public.pem" -signature /dev/stdin "$FILE" > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        ED25519_FP=$(get_pubkey_fingerprint "ed25519" "$HOME/.jarvis/keys/ed25519_public.pem")
        echo "  ✓ Ed25519 signature valid (key fingerprint: ${ED25519_FP:0:16}…)"
    else
        echo "  ✗ Ed25519 signature invalid"
        exit 1
    fi
else
    echo "  ✗ Ed25519 public key not found at ~/.jarvis/keys/ed25519_public.pem"
    exit 1
fi

echo ""
echo "✓ Dual signatures verified successfully"

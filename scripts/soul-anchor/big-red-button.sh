#!/usr/bin/env bash
# Big red button for Soul Anchor v1.1 USB/cold-root signing.
# This script never reads, creates, or stores private key material.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ANCHOR_DIR="$REPO_ROOT/.jarvis/soul_anchor"
SIGNING_DIR="$ANCHOR_DIR/signing"
SIG_DIR="$ANCHOR_DIR/signatures"
V11_DIR="$ANCHOR_DIR/v1.1"
PUB_DIR="$REPO_ROOT/Jarvis/Sources/JarvisCore/SoulAnchor/pubkeys"
PACKET="$SIGNING_DIR/soul_anchor_v1_1_packet.json"
DRAFT="$V11_DIR/genesis.draft.json"
GENESIS="$ANCHOR_DIR/genesis.json"
P256_SIG="$SIG_DIR/soul_anchor_v1_1.p256.sig"
ED_SIG="$SIG_DIR/soul_anchor_v1_1.ed25519.sig"

usage() {
  cat <<'HELP'
Soul Anchor big red button

Commands:
  prepare [--usb /Volumes/USBNAME]
      Build the v1.1 signing packet from the live canon and optionally copy it
      to the USB drive. No signatures are created.

  install --usb /Volumes/USBNAME
      Import the returned signatures from the USB drive, verify both signatures,
      and promote the new ratified genesis.json.

  status
      Print the current local Soul Anchor state.

USB expected returned files for install:
  soul_anchor_v1_1.p256.sig       ECDSA P-256 DER signature over packet
  soul_anchor_v1_1.ed25519.sig    OpenSSH SSHSIG over packet, namespace jarvis-soul-anchor
HELP
}

die() {
  printf 'ABORT: %s\n' "$*" >&2
  exit 1
}

need_file() {
  [[ -f "$1" ]] || die "missing file: $1"
}

sha256_file() {
  shasum -a 256 "$1" | awk '{print $1}'
}

usb_path=""
cmd="${1:-}"
if [[ -z "$cmd" ]]; then
  usage
  exit 2
fi
shift || true

while [[ $# -gt 0 ]]; do
  case "$1" in
    --usb)
      usb_path="${2:-}"
      [[ -n "$usb_path" ]] || die "--usb requires a path"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

prepare_packet() {
  mkdir -p "$SIGNING_DIR" "$SIG_DIR" "$V11_DIR"
  /usr/bin/python3 - "$REPO_ROOT" "$PACKET" "$DRAFT" <<'PY'
import hashlib
import json
import pathlib
import socket
import sys
from datetime import datetime, timezone

root = pathlib.Path(sys.argv[1])
packet_path = pathlib.Path(sys.argv[2])
draft_path = pathlib.Path(sys.argv[3])
pub_dir = root / "Jarvis/Sources/JarvisCore/SoulAnchor/pubkeys"

def sha_file(rel):
    return hashlib.sha256((root / rel).read_bytes()).hexdigest()

def biographical_mass_hash():
    h = hashlib.sha256()
    for name in ["1.md", "2.md", "3.md", "4.md", "5.md"]:
        h.update((root / "mcuhist" / name).read_bytes())
    return h.hexdigest()

def aragorn_hash():
    text = (root / "SOUL_ANCHOR.md").read_text(encoding="utf-8")
    marker = "## 8. Identity Lineage & Aragorn Class Binding"
    start = text.index(marker)
    tail = text[start:]
    end = tail.find("\n---", 1)
    section = tail[:end] if end != -1 else tail
    payload = {"section8Markdown": section.strip()}
    data = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(data).hexdigest()

def read_fingerprint(name):
    path = pub_dir / name
    return path.read_text(encoding="utf-8").strip()

canon = {
    "PRINCIPLES.md": sha_file("PRINCIPLES.md"),
    "VERIFICATION_PROTOCOL.md": sha_file("VERIFICATION_PROTOCOL.md"),
    "SOUL_ANCHOR.md": sha_file("SOUL_ANCHOR.md"),
    "mcuhist/MANIFEST.md": sha_file("mcuhist/MANIFEST.md"),
    "mcuhist/REALIGNMENT_1218.md": sha_file("mcuhist/REALIGNMENT_1218.md"),
    "biographical_mass_hash": biographical_mass_hash(),
    "aragorn_class_designation": aragorn_hash(),
}

packet = {
    "schema_version": "1.1.0",
    "kind": "jarvis-soul-anchor-signing-packet",
    "created_utc": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
    "operator": {
        "legal_name": "Robert Barclay Hanson",
        "callsign": "Grizz",
        "credentials": "EMT-P Ret., Founder GrizzlyMedicine Research Institute",
    },
    "host": {
        "hostname": socket.gethostname(),
    },
    "canon": canon,
    "key_fingerprints": {
        "p256_operational": read_fingerprint("p256.fingerprint"),
        "ed25519_cold_root": read_fingerprint("ed25519.fingerprint"),
    },
}

packet_bytes = json.dumps(packet, sort_keys=True, separators=(",", ":")).encode("utf-8")
packet_path.write_bytes(packet_bytes)
packet_hash = hashlib.sha256(packet_bytes).hexdigest()

draft = {
    "version": "1.1.0",
    "status": "DRAFT",
    "operator": packet["operator"],
    "canon": canon,
    "signing_packet_file": ".jarvis/soul_anchor/signing/soul_anchor_v1_1_packet.json",
    "signing_packet_sha256": packet_hash,
    "keys": {
        "ed25519_cold_root": {
            "pubkey_sha256_fingerprint": packet["key_fingerprints"]["ed25519_cold_root"],
            "private_location": "USB cold root / operator safety-deposit workflow",
            "signature_file": ".jarvis/soul_anchor/signatures/soul_anchor_v1_1.ed25519.sig",
            "signature_format": "SSHSIG / namespace jarvis-soul-anchor",
            "verify_identity": "grizz@gmri",
        },
        "p256_operational": {
            "pubkey_sha256_fingerprint": packet["key_fingerprints"]["p256_operational"],
            "private_location": "operator-controlled P-256 root",
            "signature_file": ".jarvis/soul_anchor/signatures/soul_anchor_v1_1.p256.sig",
            "signature_format": "ECDSA P-256 DER",
        },
    },
}
draft_path.write_text(json.dumps(draft, indent=2, sort_keys=True) + "\n", encoding="utf-8")

print(packet_hash)
PY
}

write_usb_instructions() {
  local target="$1"
  cat > "$target/READ_ME_FIRST_SOUL_ANCHOR.txt" <<'TXT'
JARVIS Soul Anchor v1.1 signing packet is on this USB.

Sign this exact file:
  soul_anchor_v1_1_packet.json

Return these two files to the USB root:
  soul_anchor_v1_1.p256.sig
  soul_anchor_v1_1.ed25519.sig

Example P-256 command if your P-256 private key is on the USB as p256_private.pem:
  openssl dgst -sha256 -sign p256_private.pem -out soul_anchor_v1_1.p256.sig soul_anchor_v1_1_packet.json

Example Ed25519 SSHSIG command if your cold key is on the USB as ed25519_cold:
  ssh-keygen -Y sign -f ed25519_cold -n jarvis-soul-anchor soul_anchor_v1_1_packet.json
  mv soul_anchor_v1_1_packet.json.sig soul_anchor_v1_1.ed25519.sig

Do not copy private key files back to the Mac.
TXT
}

verify_imported_signatures() {
  need_file "$PACKET"
  need_file "$P256_SIG"
  need_file "$ED_SIG"
  openssl dgst -sha256 \
    -verify "$PUB_DIR/p256.pub.der" \
    -keyform DER \
    -signature "$P256_SIG" \
    "$PACKET" >/dev/null
  ssh-keygen -Y verify \
    -f "$PUB_DIR/allowed_signers" \
    -I grizz@gmri \
    -n jarvis-soul-anchor \
    -s "$ED_SIG" \
    < "$PACKET" >/dev/null
}

case "$cmd" in
  prepare)
    packet_hash="$(prepare_packet)"
    printf 'Prepared Soul Anchor v1.1 packet:\n  %s\nsha256:\n  %s\n' "$PACKET" "$packet_hash"
    if [[ -n "$usb_path" ]]; then
      [[ -d "$usb_path" ]] || die "USB path is not mounted: $usb_path"
      cp "$PACKET" "$usb_path/soul_anchor_v1_1_packet.json"
      write_usb_instructions "$usb_path"
      sync
      printf 'Copied packet and plain-English instructions to:\n  %s\n' "$usb_path"
    fi
    ;;

  install)
    [[ -n "$usb_path" ]] || die "install requires --usb /Volumes/USBNAME"
    [[ -d "$usb_path" ]] || die "USB path is not mounted: $usb_path"
    prepare_packet >/dev/null
    need_file "$usb_path/soul_anchor_v1_1.p256.sig"
    need_file "$usb_path/soul_anchor_v1_1.ed25519.sig"
    cp "$usb_path/soul_anchor_v1_1.p256.sig" "$P256_SIG"
    cp "$usb_path/soul_anchor_v1_1.ed25519.sig" "$ED_SIG"
    verify_imported_signatures
    /usr/bin/python3 - "$DRAFT" "$GENESIS" "$P256_SIG" "$ED_SIG" <<'PY'
import hashlib
import json
import pathlib
import sys
from datetime import datetime, timezone

draft_path = pathlib.Path(sys.argv[1])
genesis_path = pathlib.Path(sys.argv[2])
p256_sig = pathlib.Path(sys.argv[3])
ed_sig = pathlib.Path(sys.argv[4])

genesis = json.loads(draft_path.read_text(encoding="utf-8"))
genesis["status"] = "RATIFIED"
genesis["ratified_utc"] = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
genesis["keys"]["p256_operational"]["signature_sha256"] = hashlib.sha256(p256_sig.read_bytes()).hexdigest()
genesis["keys"]["ed25519_cold_root"]["signature_sha256"] = hashlib.sha256(ed_sig.read_bytes()).hexdigest()

if genesis_path.exists():
    backup = genesis_path.with_name("genesis.backup." + datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ") + ".json")
    backup.write_bytes(genesis_path.read_bytes())

genesis_path.write_text(json.dumps(genesis, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
    printf 'Soul Anchor v1.1 installed and dual signatures verified:\n  %s\n' "$GENESIS"
    ;;

  status)
    if [[ -f "$GENESIS" ]]; then
      /usr/bin/python3 - "$GENESIS" <<'PY'
import json
import pathlib
import sys
g = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
print("version:", g.get("version", "<missing>"))
print("status:", g.get("status", "<missing>"))
print("ratified_utc:", g.get("ratified_utc", "<missing>"))
print("signing_packet_sha256:", g.get("signing_packet_sha256", "<missing>"))
print("canon_bindings:", len(g.get("canon", {})))
PY
    else
      printf 'No genesis.json at %s\n' "$GENESIS"
      exit 1
    fi
    ;;

  *)
    usage
    exit 2
    ;;
esac

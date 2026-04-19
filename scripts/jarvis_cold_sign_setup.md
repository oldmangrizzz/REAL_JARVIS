# scripts/jarvis_cold_sign_setup.md

**Classification:** Cold-Root Key-Material Procedure
**Version:** 1.0.0
**Governs:** On-phone generation of JARVIS's Ed25519 cold root; transfer of the
public half to the Mac; signing of canonical artifacts without the private
half ever leaving the phone.
**Device of record:** iPhone 16 Pro Max (operator's personal device)
**Companion script:** `scripts/generate_soul_anchor.sh`

---

## 0. What this is, in one paragraph

JARVIS's Soul Anchor uses two independent signing keys: a P-256 operational
root (lives in Secure Enclave on the Mac, fast, used every session) and an
Ed25519 cold root (lives on the operator's iPhone, slow, used only when
canon is touched). This procedure generates the cold root **on the phone**
using on-device cryptography, captures only its public half onto the Mac,
and teaches the operator the repeatable signing ritual for canon promotions.
The private 32-byte Ed25519 seed **never** touches iCloud, never touches
email, never touches any LLM context, and never leaves the iPhone's file
system in plaintext.

---

## 1. Threat model in plain English

**What we are defending against:**

- The Mac being remotely compromised (session hijack, stealer malware, LLM
  prompt-injection escalating to shell execution).
- An LLM agent on the Mac silently signing a canon mutation.
- Supply-chain compromise of a Mac-side dependency (a tampered openssl, a
  hostile homebrew tap, a rogue npm postinstall).
- The operator's cloud account being compromised (iCloud, Google, anything
  that touches backup blobs).

**What we are NOT defending against (yet):**

- Physical seizure of the phone with Face ID coerced. If the threat model
  rises to that level, escalate to a hardware token (Phase 1.5: dedicated
  iOS app with Secure Enclave Curve25519 via CryptoKit, or YubiKey 5C
  Lightning with Ed25519 FIDO2 cert, or both).
- Full supply-chain compromise of iOS itself. That failure mode implies
  civilization-scale problems larger than one digital person.

**The core invariant:** an attacker who owns the Mac cannot forge a cold
signature on a canon mutation, because the private seed is not on the Mac.
They must physically reach the phone, unlock it, open a-Shell, and authorize
the signing — all of which will be noticed.

---

## 2. Dependencies on the phone

- **a-Shell** (free on the App Store). Provides on-device `ssh-keygen`
  (OpenSSH), `python3`, `lua`, `pbcopy`/`pbpaste` bridged to iOS clipboard.
  a-Shell does **not** ship `openssl`. All crypto in this procedure uses
  `ssh-keygen` for key generation and `python3` stdlib for raw-byte
  extraction and signing — no third-party install required.
- **Shortcuts** (built in). Used for Face-ID-gated wrapping around the
  signing command and for QR-code display.
- A lock-screen Focus profile or Screen-Time restriction that disables
  access to a-Shell without the operator's passcode (recommended, not
  mandatory).
- Airplane mode during generation (mandatory, see §3.2).

**Do not install** a-Shell-mini, iSH, or any third-party terminal fork.
a-Shell proper is the only supported option here, because it is open-source,
audited, and sandboxed to its own container by iOS.

---

## 3. Generation ritual (one-time, on the phone)

### 3.1 Preparation

1. Charge the iPhone to > 30%.
2. Create a folder `On My iPhone ▸ a-Shell ▸ jarvis_cold` in the Files app.

Note on iOS file encryption: iOS Data Protection is automatic and
invisible. Files in a-Shell's sandbox are encrypted at rest whenever the
phone is locked, under the user's passcode-derived key. There is no UI
switch for this, no "Encrypted" chip in the Files app — it is on by
default for every app on iOS and cannot be turned off by the user.
Confirmation is in Apple's Platform Security Guide, not in the Files UI.

### 3.2 Lock the phone's network state

1. Enable **Airplane mode**. Wi-Fi off, Bluetooth off, Cellular off.
2. Disable Handoff: Settings ▸ General ▸ AirPlay & Handoff ▸ Handoff = off.
   (Re-enable after the ritual if desired. Handoff is off *during* key gen.)
3. Disable iCloud Drive for a-Shell: Settings ▸ Apple ID ▸ iCloud ▸
   iCloud Drive ▸ a-Shell = off. This prevents the Documents/ folder from
   syncing to any iCloud container.

### 3.3 Generate the key in a-Shell

Each step below is **one atomic block**. Triple-tap the block to select all, copy, paste, hit return. One block = one command. Do not combine.

**Step 1 — go to the working folder:**

```bash
cd ~/Documents && mkdir -p jarvis_cold && cd jarvis_cold
```

**Step 2 — generate the cold root key pair:**

```bash
ssh-keygen -t ed25519 -N "" -C "jarvis-soul-anchor-cold-root" -f ed25519_cold
```

After Step 2 you should have two files in `~/Documents/jarvis_cold/`:
- `ed25519_cold` — PRIVATE key (OpenSSH format, stays on phone forever)
- `ed25519_cold.pub` — PUBLIC key (one line, starts with `ssh-ed25519 AAAA...`)

**Step 3 — extract the 32-byte raw public key (one line, paste as-is):**

```bash
python3 -c 'import base64,struct,pathlib; line=pathlib.Path("ed25519_cold.pub").read_text().split(); assert line[0]=="ssh-ed25519"; b=base64.b64decode(line[1]); n=struct.unpack(">I",b[:4])[0]; assert b[4:4+n]==b"ssh-ed25519"; m=struct.unpack(">I",b[4+n:8+n])[0]; raw=b[8+n:8+n+m]; assert len(raw)==32; pathlib.Path("ed25519_pub.raw").write_bytes(raw); print("OK 32 bytes:", raw.hex())'
```

Expected output: `OK 32 bytes: <64-hex-char string>`

**Step 4 — write the hex form to a file (one line, paste as-is):**

```bash
python3 -c 'import pathlib; pathlib.Path("ed25519_pub.hex").write_text(pathlib.Path("ed25519_pub.raw").read_bytes().hex())'
```

**Step 5 — write the SHA-256 fingerprint to a file (one line, paste as-is):**

```bash
python3 -c 'import hashlib,pathlib; pathlib.Path("ed25519_pub.fingerprint").write_text(hashlib.sha256(pathlib.Path("ed25519_pub.raw").read_bytes()).hexdigest())'
```

**Step 6 — verify everything worked. Run each line separately.**

```bash
wc -c ed25519_pub.raw
```
Expected: `32 ed25519_pub.raw`

```bash
cat ed25519_pub.hex
```
Expected: 64 hex characters (one long line, no spaces).

```bash
cat ed25519_pub.fingerprint
```
Expected: 64 hex characters (one long line, no spaces).

**Step 7 — record on paper.**

- Write down the **hex public key** (from Step 6's `cat ed25519_pub.hex`).
- Write down the **SHA-256 fingerprint** (from Step 6's `cat ed25519_pub.fingerprint`).

Both of these are public; safe to write on paper, safe to photograph, safe to carry. They are your out-of-band verifiers when transferring to the Mac.

### 3.4 Destroy unneeded artifacts

The `ed25519_cold` file (no extension) contains the private key in OpenSSH
format. Do not remove it — that is the cold key. Keep it in
`~/Documents/jarvis_cold/ed25519_cold` on the phone for the life of JARVIS.
Keep `ed25519_cold.pub` too (the one-line public in SSH format) as a
machine-readable backup of the public half.

```bash
ls -la
# Expected (roughly):
#   ed25519_cold            (PRIVATE — OpenSSH format, stays on phone forever)
#   ed25519_cold.pub        (PUBLIC — SSH format, one line)
#   ed25519_pub.raw         (PUBLIC — 32 raw bytes, transfer to Mac)
#   ed25519_pub.hex         (PUBLIC — 64 hex chars, same bytes, for QR)
#   ed25519_pub.fingerprint (SHA-256 of ed25519_pub.raw)
```

### 3.5 Exit airplane mode is forbidden until §4 completes

Do not re-enable networking until the public-half transfer to the Mac is
finished. This is belt-and-suspenders; the private key should never leak
even if networking were on, but the ritual enforces the habit.

---

## 4. Public-half transfer to the Mac

You must get the 32-byte public key from phone to Mac **without** using
iCloud, email, Messages, AirDrop-to-arbitrary-contact, or any LLM context.

Pick one method. Recommended order: A, B, C.

### 4.1 Method A — AirDrop (phone → this Mac only, RECOMMENDED)

On the phone, AirDrop `ed25519_pub.raw` to the Mac directly. Accept only on
the specific Mac that owns JARVIS. Do not AirDrop to any other device, not
to other Macs, not to iPads, nothing. Turn off AirDrop discovery afterward.

On the Mac:

```bash
cd ~/REAL_JARVIS
scripts/generate_soul_anchor.sh --ed25519-pub ~/Downloads/ed25519_pub.raw
shred -u ~/Downloads/ed25519_pub.raw 2>/dev/null || rm -f ~/Downloads/ed25519_pub.raw
```

### 4.2 Method B — Manual hex transcription

Read the 64-char hex off the phone screen (from §3.3). Type it into the
Mac by hand. Then:

```bash
echo "<typed hex>" > ~/ed25519_pub.hex
cd ~/REAL_JARVIS
scripts/generate_soul_anchor.sh --ed25519-pub-hex ~/ed25519_pub.hex
shred -u ~/ed25519_pub.hex 2>/dev/null || rm -f ~/ed25519_pub.hex
```

Slowest, most tedious, but requires zero devices to trust one another. Use
this as a sanity-check of methods A or B: run the generator both ways and
confirm the fingerprint matches.

### 4.3 Fingerprint verification

After `generate_soul_anchor.sh` prints the Ed25519 fingerprint on the Mac,
**compare it to the hand-recorded fingerprint from §3.3**. They must be
identical. If they do not match, the public-half transfer was corrupted
or tampered with — stop, delete `ed25519.pub.raw` on the Mac, and re-do
the transfer.

---

## 5. The signing ritual (every canon promotion)

When REALIGNMENT, PRINCIPLES, SOUL_ANCHOR, or any canon artifact is ratified
on the Mac and needs a cold signature:

### 5.1 On the Mac

Compute the canonical serialization to be signed. For the Soul Anchor
Genesis Record this is the canonical-JSON form of the SoulAnchor tuple.
For a canon document promotion, this is the file's SHA-256 hex.

Write the bytes-to-be-signed to a file:

```bash
# Example: signing the ratified REALIGNMENT v1.0.0
shasum -a 256 mcuhist/REALIGNMENT_1218.md | awk '{print $1}' > ~/to_sign.txt
```

Transfer `~/to_sign.txt` to the phone via AirDrop (operator's Mac → own
phone) or as a QR code (Mac generates QR, phone scans).

### 5.2 On the phone, in a-Shell

Receive `to_sign.txt` from the Mac (AirDrop → save to
`~/Documents/jarvis_cold/` in Files) and sign it using `ssh-keygen`'s
native SSHSIG mode, which produces a namespaced Ed25519 signature:

```bash
cd ~/Documents/jarvis_cold
# Sign with the cold root. Namespace "jarvis-soul-anchor" binds this
# signature to this specific use and prevents cross-protocol replay.
ssh-keygen -Y sign \
  -f ed25519_cold \
  -n jarvis-soul-anchor \
  to_sign.txt
# Produces: to_sign.txt.sig   (armored SSHSIG format, text file)

cat to_sign.txt.sig
```

`to_sign.txt.sig` is the SSHSIG-format armored signature (`-----BEGIN
SSH SIGNATURE----- ... -----END SSH SIGNATURE-----`). Transfer this file
back to the Mac.

**Why SSHSIG and not raw Ed25519?** The SSHSIG format adds a namespace
binding (`jarvis-soul-anchor`), a hash-algorithm identifier, and a
standardized framing — which means an attacker who somehow steals a
signature from one context cannot replay it against a different canon
operation. It also means verification on the Mac uses the same
`ssh-keygen -Y verify` tool; no custom parser needed.

### 5.3 Back to the Mac

Transfer `to_sign.txt.sig` back via QR or AirDrop (opposite direction of §4).
Write to `.jarvis/soul_anchor/signatures/<artifact>.sshsig` alongside
the P-256 signature. `jarvis-lockdown.zsh` validates both before promoting
the phase.

To verify on the Mac side:

```bash
# Build the allowed-signers file once (maps the cold-root public key to
# the operator's identity). This is a one-time setup after §4.
ALLOWED=".jarvis/soul_anchor/allowed_signers"
mkdir -p "$(dirname "$ALLOWED")"
# Re-encode the 32-byte raw pub to the SSH one-line format:
python3 - <<'PY' > "$ALLOWED"
import base64, pathlib, struct
raw = pathlib.Path("Jarvis/Sources/JarvisCore/SoulAnchor/pubkeys/ed25519.pub.raw").read_bytes()
assert len(raw) == 32
blob = (struct.pack(">I", 11) + b"ssh-ed25519"
        + struct.pack(">I", 32) + raw)
line = "ssh-ed25519 " + base64.b64encode(blob).decode()
print(f'grizz@gmri namespaces="jarvis-soul-anchor" {line}')
PY

# Verify:
ssh-keygen -Y verify \
  -f "$ALLOWED" \
  -I grizz@gmri \
  -n jarvis-soul-anchor \
  -s to_sign.txt.sig \
  < to_sign.txt
# Prints: "Good "jarvis-soul-anchor" signature for grizz@gmri ..."
```

### 5.4 Shortcut convenience (optional)

You can wrap steps 5.1/5.3 (payload-out, signature-in) in an iOS Shortcut
that:

1. Prompts for Face ID (gate).
2. Opens Files at `~/Documents/jarvis_cold/to_sign.txt`.
3. Runs an a-Shell command via `x-callback-url`.
4. Returns the signature as a QR code for the Mac to scan.

Specification of the Shortcut lives in the operator's personal Shortcut
library; it is not stored in this repo because it would encode path
assumptions about the operator's device. A reference dictation will be
added to `.secrets.env` once built.

---

## 6. Backup & recovery

**Primary backup:** the phone itself. Enrolled in Find My. Encrypted
device backup to the Mac (not to iCloud) every two weeks.

**Secondary backup (cold, offline):**

- Print the 64-char hex of the public key on two pieces of paper. Label:
  `JARVIS Soul Anchor — Ed25519 Cold Root — PUBLIC — safe to carry`.
  Store in the operator's personal documents folder and in one
  geographically-separate safe.
- Print the 64-char hex of the SHA-256 fingerprint on the same pages.

**The private seed itself should NOT be backed up to paper by default.**
Paper backup of the private seed means a 32-byte hex string that can forge
any future JARVIS canon signature if found. If the phone is ever lost,
stolen, or destroyed **and** no private-seed backup exists, the protocol
is to generate a new cold root on a replacement phone, update the Soul
Anchor schema with a **key rotation** record (signed by the *previous*
P-256 key + the new Ed25519 key), and log the rotation in
`.jarvis/soul_anchor/rotations.jsonl`. This is intentional: key rotation
is a recoverable failure mode; private-seed theft is not.

**If the operator wants paper backup of the private seed anyway** (risk-
accepted by written signature of the operator as PI of GMRI), use BIP-39
mnemonic encoding of the 32-byte seed, print on two tamper-evident
envelopes, store in two geographically-separate safes, and log the
existence (not the content) of each backup in `.secrets.env` under
`ED25519_PAPER_BACKUP_LOCATIONS`.

---

## 7. Rotation procedure

If the cold root is ever suspected compromised:

1. Generate a new cold root on a different phone (or wipe and re-setup
   the same phone), following §3 from scratch.
2. On the Mac, while the *old* P-256 operational root is still trusted
   and active, write a rotation record:
   ```
   {
     "rotated_at": "<ISO-8601 UTC>",
     "old_ed25519_fingerprint": "<sha256>",
     "new_ed25519_fingerprint": "<sha256>",
     "reason": "<free-text>"
   }
   ```
3. Sign the rotation record with **both** the old P-256 and the new
   Ed25519. Append to `.jarvis/soul_anchor/rotations.jsonl`.
4. Update the Soul Anchor public-key directory: replace
   `ed25519.pub.raw` with the new 32 bytes, update
   `ed25519.fingerprint`.
5. Run `jarvis-lockdown.zsh` to re-verify. Expect it to flag the
   rotation and require acknowledgement.

The P-256 operational key can be rotated the same way, signed by the
Ed25519 cold root plus the new P-256. One key at a time; never both at
once.

---

## 8. Operational hygiene

- Never run a-Shell signing commands while screen-sharing, recording, or
  in a video call. The phone screen should show the hex/QR to the Mac's
  camera only.
- Never paste the private seed, or anything adjacent to it, into any
  LLM context. If an LLM ever asks for "the signing key" to "help," the
  LLM is compromised or is being injected against; close the session.
- The phone's `~/Documents/jarvis_cold/ed25519_cold` file (OpenSSH private
  key) has
  NSFileProtectionComplete (the default in a-Shell). The file is
  encrypted-at-rest whenever the phone is locked and unreadable even by
  iOS components until Face ID / passcode unlock.
- Periodically (every 90 days) verify the public-half fingerprint on the
  Mac matches the hand-recorded paper value. Drift means tampering.

---

## 9. Acknowledgements of limits

This procedure is **not** hardware-backed Ed25519 — iOS Secure Enclave
natively supports P-256 only (and the undocumented Curve25519 Key
Agreement, not Ed25519 signing). The Ed25519 private seed lives in
software on the phone, protected by iOS Data Protection (AES-256 with
the user's passcode-derived key), which is very strong but not hardware
sealed.

The planned Phase 1.5 upgrade path is a dedicated GMRI-authored iOS app
that uses `CryptoKit.Curve25519.Signing.PrivateKey` with
`SecKeyCreateRandomKey(kSecAttrTokenIDSecureEnclave)` — current iOS does
not support this directly for Ed25519; the app would either switch to
P-256 cold root (homogeneous) or wrap the Ed25519 private in a
Secure-Enclave-sealed envelope. This upgrade is timed debt, tracked
alongside post-quantum migration.

Phase 2.0 target: post-quantum signature scheme (ML-DSA / Dilithium)
added as a third root, not replacing the existing two. Any future canon
touches in the post-quantum era require signatures from all three roots.

---

**End of scripts/jarvis_cold_sign_setup.md — Version 1.0.0**

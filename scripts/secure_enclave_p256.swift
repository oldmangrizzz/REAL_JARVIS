#!/usr/bin/env swift
// JARVIS P-256 Secure Enclave helper.
//
// Subcommands:
//   init   <pub.der.path> <handle.path>         create SE key, emit public DER + handle blob
//   sign   <handle.path>  <input>  <sig.out>    sign input file with SE key, write raw ECDSA sig
//   verify <pub.der.path> <input>  <sig.in>     verify signature with public key
//
// The handle blob is the CryptoKit dataRepresentation: an encrypted reference
// that ONLY this Mac's Secure Enclave can decrypt. It is safe at rest but
// must be kept in the jarvis private directory.

import Foundation
import CryptoKit

func die(_ s: String) -> Never { FileHandle.standardError.write(Data((s + "\n").utf8)); exit(1) }

let args = CommandLine.arguments
guard args.count >= 2 else { die("usage: \(args[0]) init|sign|verify ...") }

switch args[1] {

case "init":
    guard args.count == 4 else { die("usage: init <pub.der.path> <handle.path>") }
    let pubPath = args[2], handlePath = args[3]
    guard SecureEnclave.isAvailable else { die("Secure Enclave not available on this machine") }
    let key: SecureEnclave.P256.Signing.PrivateKey
    do { key = try SecureEnclave.P256.Signing.PrivateKey(accessControl:
        SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, [.privateKeyUsage], nil)!)
    } catch { die("SE keygen failed: \(error)") }
    try! key.publicKey.derRepresentation.write(to: URL(fileURLWithPath: pubPath))
    let handleURL = URL(fileURLWithPath: handlePath)
    try! key.dataRepresentation.write(to: handleURL)
    try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: handlePath)
    print("SE P-256 key created")
    print("  public DER: \(pubPath)")
    print("  handle:     \(handlePath)")

case "sign":
    guard args.count == 5 else { die("usage: sign <handle.path> <input> <sig.out>") }
    let handlePath = args[2], input = args[3], sigOut = args[4]
    let handle = try! Data(contentsOf: URL(fileURLWithPath: handlePath))
    let key: SecureEnclave.P256.Signing.PrivateKey
    do { key = try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: handle) }
    catch { die("SE key load failed: \(error)") }
    let data = try! Data(contentsOf: URL(fileURLWithPath: input))
    let sig: P256.Signing.ECDSASignature
    do { sig = try key.signature(for: data) }
    catch { die("sign failed: \(error)") }
    try! sig.derRepresentation.write(to: URL(fileURLWithPath: sigOut))
    print("signed: \(sigOut) (\(sig.derRepresentation.count) bytes, DER ECDSA)")

case "verify":
    guard args.count == 5 else { die("usage: verify <pub.der.path> <input> <sig.in>") }
    let pubPath = args[2], input = args[3], sigIn = args[4]
    let pubData = try! Data(contentsOf: URL(fileURLWithPath: pubPath))
    let pub: P256.Signing.PublicKey
    do { pub = try P256.Signing.PublicKey(derRepresentation: pubData) }
    catch { die("pub key load failed: \(error)") }
    let sigData = try! Data(contentsOf: URL(fileURLWithPath: sigIn))
    let sig: P256.Signing.ECDSASignature
    do { sig = try P256.Signing.ECDSASignature(derRepresentation: sigData) }
    catch { die("sig parse failed: \(error)") }
    let data = try! Data(contentsOf: URL(fileURLWithPath: input))
    if pub.isValidSignature(sig, for: data) {
        print("OK: signature valid")
    } else {
        die("BAD: signature invalid")
    }

default:
    die("unknown subcommand: \(args[1])")
}

#!/usr/bin/env sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright 2026 Deadband Inc.
#
# Host side of DeviceID attestation
#
# DeviceID TA gives a P-256 public key and signs SHA-256("dbl-attest-v1" || nonce) (see dbl_tee.h).
# Certificate for this key is stored in the dbl-bootid "deviceid" slot.
#
# Usage:
#   dbl-deviceid.sh verify PUBKEY NONCE SIG
#   dbl-deviceid.sh issue CA_CRT CA_KEY PUBKEY SUBJECT OUT
#   dbl-deviceid.sh check CA_CRT CERT NONCE SIG
#
#   PUBKEY  output of "dbl-tee deviceid-pubkey"
#   NONCE   hex, 1-64 bytes
#   SIG     output of "dbl-tee attest NONCE"
#   CERT    DER certificate, trailing 0xff padding ignored
#           (output of "dbl-bootid read deviceid")
#
# verify: SIG verifies with PUBKEY, showing the key is live in the TA.
# issue: certificate for PUBKEY, DER: SUBJECT in openssl -subj form, random
#   serial, no expiry, CA:FALSE, digitalSignature. CA_KEY is a PEM file or a
#   pkcs11: URI (libp11 engine and PIN in OPENSSL_CONF).
# check: CERT chains to CA_CRT (validity dates ignored) and SIG verifies with
#   the CERT key. Prints the CERT subject.
#
# Example application:
#   nonce=$(openssl rand -hex 32)
#   sig=$(ssh unit dbl-tee attest "$nonce")
#   ssh unit dbl-bootid read deviceid /dev/stdout >deviceid.der
#   dbl-deviceid.sh check ca.crt deviceid.der "$nonce" "$sig"
set -eu

usage() {
  sed -n '10,13s/^# \{0,1\}//p' "$0" >&2
  exit 2
}

fail() {
  echo "dbl-deviceid: $*" >&2
  exit 1
}

tmp=$(mktemp -d)
trap 'rm -rf "${tmp:?}"' EXIT

# Writes $tmp/pub.pem from SEC1 uncompressed hex
pubkey_pem() {
  printf %s "$1" | grep -Eqx '04[0-9a-fA-F]{128}' ||
    fail "PUBKEY: 65 bytes as hex, SEC1 uncompressed"
  # P-256 SubjectPublicKeyInfo header
  printf '3059301306072a8648ce3d020106082a8648ce3d030107034200%s' "$1" |
    xxd -r -p | openssl pkey -pubin -inform DER -out "$tmp/pub.pem" ||
    fail "PUBKEY: not a P-256 point"
}

# Checks SIG ($2, r || s) over the prefix and NONCE ($1) with $tmp/pub.pem
verify_sig() {
  printf %s "$1" | grep -Eqx '([0-9a-fA-F]{2}){1,64}' ||
    fail "NONCE: 1-64 bytes as hex"
  printf %s "$2" | grep -Eqx '[0-9a-fA-F]{128}' || fail "SIG: 64 bytes as hex"
  {
    printf dbl-attest-v1
    printf %s "$1" | xxd -r -p
  } >"$tmp/msg"
  printf 'asn1=SEQUENCE:sig\n[sig]\nr=INTEGER:0x%s\ns=INTEGER:0x%s\n' \
    "$(printf %s "$2" | cut -c1-64)" "$(printf %s "$2" | cut -c65-128)" >"$tmp/sig.cnf"
  openssl asn1parse -genconf "$tmp/sig.cnf" -noout -out "$tmp/sig.der"
  openssl dgst -sha256 -verify "$tmp/pub.pem" -signature "$tmp/sig.der" \
    "$tmp/msg" >/dev/null || fail "signature does not verify"
}

# Checks that certificate $2 (PEM) chains to CA certificate $1
verify_chain() {
  openssl verify -no_check_time -x509_strict -CAfile "$1" "$2" >/dev/null ||
    fail "certificate does not chain to $1"
}

case ${1:-} in
  verify)
    [ $# -eq 4 ] || usage
    pubkey_pem "$2"
    verify_sig "$3" "$4"
    ;;
  issue)
    [ $# -eq 6 ] || usage
    ca_crt=$2 ca_key=$3 subject=$5 out=$6
    pubkey_pem "$4"
    printf '%s\n' basicConstraints=critical,CA:FALSE \
      keyUsage=critical,digitalSignature subjectKeyIdentifier=none \
      authorityKeyIdentifier=keyid >"$tmp/ext"
    case $ca_key in
      pkcs11:*) set -- -engine pkcs11 -CAkeyform engine ;;
      *) set -- ;;
    esac
    # With No -set_serial OpenSSL selects random 159-bit serial
    openssl x509 -new -force_pubkey "$tmp/pub.pem" -subj "$subject" \
      -CA "$ca_crt" -CAkey "$ca_key" "$@" -sha256 \
      -not_after 99991231235959Z -extfile "$tmp/ext" -out "$tmp/cert.pem"
    verify_chain "$ca_crt" "$tmp/cert.pem"
    openssl x509 -in "$tmp/cert.pem" -outform DER -out "$out"
    ;;
  check)
    [ $# -eq 5 ] || usage
    openssl x509 -inform DER -in "$3" -out "$tmp/cert.pem" 2>/dev/null ||
      fail "CERT: not a DER certificate"
    verify_chain "$2" "$tmp/cert.pem"
    openssl x509 -in "$tmp/cert.pem" -noout -pubkey >"$tmp/pub.pem"
    verify_sig "$4" "$5"
    openssl x509 -in "$tmp/cert.pem" -noout -subject
    ;;
  *)
    usage
    ;;
esac

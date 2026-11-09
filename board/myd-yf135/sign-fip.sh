#!/usr/bin/env sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright 2026 Deadband Inc.
#
# Re-sign the TF-A TBB certificates of a finished FIP keeping all images and fw_config
#
# USAGE: sign-fip.sh [-p <pub.pem>] <fip.bin> <key>
#   key: P-256 PEM file, or PKCS#11 URI (pkcs11 engine config via OPENSSL_CONF)
#   -p:  refuse unless the new certificates carry this public key
# /ENDUSAGE
# Requires cert_create + fiptool (TF-A build tools/) and openssl in PATH
set -eu

usage() {
  sed -n '/^# \/ENDUSAGE/q; /^# USAGE:/,$s/^# \{0,1\}//p' "$0" >&2
  exit 2
}

pub=
if [ "${1:-}" = -p ]; then
  [ "$#" -ge 2 ] || usage
  pub=$2
  shift 2
fi
[ "$#" -eq 2 ] || usage

fip=$1
key=$2

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

fiptool unpack --out "$work" "$fip" >/dev/null

# Certificates in the FIP = certificates to re-create (all or none)
certs="trusted-key-cert tos-fw-key-cert nt-fw-key-cert tos-fw-cert nt-fw-cert stm32mp-cfg-cert"
for c in $certs; do
  if [ ! -f "$work/$c.bin" ]; then
    echo "sign-fip: $fip has no $c (TBB off?)" >&2
    exit 1
  fi
done

# Args: new certificate files, images covered by the certificates
mkdir "$work/new"
: >"$work/empty"
set --
for c in $certs; do
  set -- "$@" "--$c" "$work/new/$c.bin"
done
for i in tos-fw tos-fw-extra1 tos-fw-extra2 tos-fw-config nt-fw nt-fw-config fw-config; do
  if [ -f "$work/$i.bin" ]; then
    set -- "$@" "--$i" "$work/$i.bin"
  elif [ "$i" = tos-fw-extra2 ]; then
    set -- "$@" "--$i" "$work/empty"
  fi
done

# cert_create loads every key role (including the unused SCP/SoC ones)
cert_create --key-alg ecdsa --hash-alg sha256 --tfw-nvctr 0 --ntfw-nvctr 0 \
  --rot-key "$key" --trusted-world-key "$key" --non-trusted-world-key "$key" \
  --scp-fw-key "$key" --soc-fw-key "$key" --tos-fw-key "$key" --nt-fw-key "$key" \
  "$@" >"$work/cert.log" 2>&1 || {
  cat "$work/cert.log" >&2
  echo "sign-fip: cert_create failed" >&2
  exit 1
}

# TBBR extensions: NV counters + image hashes, public keys dropped
tbbr_exts() {
  openssl asn1parse -inform DER -in "$1" |
    awk '/OBJECT *:1\.3\.6\.1\.4\.1\.4128\./ { oid = $NF }
         oid && /HEX DUMP/ { print oid, $NF; oid = "" }' |
    grep -v 'A8648CE3D0201'
}

# Each certificate is self-signed by the key: check signature and key,
# and check it covers the same images as the build's certificate
want=
[ -n "$pub" ] && want=$(openssl pkey -pubin -in "$pub" -outform DER | sha256sum)
for c in $certs; do
  openssl x509 -inform DER -in "$work/new/$c.bin" -out "$work/new/$c.pem"
  if ! openssl verify -ignore_critical -check_ss_sig -CAfile "$work/new/$c.pem" \
    "$work/new/$c.pem" >/dev/null 2>&1; then
    echo "sign-fip: $c signature does not verify" >&2
    exit 1
  fi
  got=$(openssl x509 -in "$work/new/$c.pem" -noout -pubkey | openssl pkey -pubin -outform DER | sha256sum)
  if [ -n "$want" ] && [ "$got" != "$want" ]; then
    echo "sign-fip: $c not signed by $pub" >&2
    exit 1
  fi
  if [ "$(tbbr_exts "$work/new/$c.bin")" != "$(tbbr_exts "$work/$c.bin")" ]; then
    echo "sign-fip: $c covers other images than the build's" >&2
    exit 1
  fi
done

set --
for c in $certs; do
  set -- "$@" "--$c" "$work/new/$c.bin"
done
fiptool update "$@" --out "$work/signed.fip" "$fip"

# Images must come through unchanged
mkdir "$work/check"
fiptool unpack --out "$work/check" "$work/signed.fip" >/dev/null
for f in "$work"/*.bin; do
  n=$(basename "$f")
  case " $certs " in *" ${n%.bin} "*) continue ;; esac
  cmp -s "$f" "$work/check/$n" || {
    echo "sign-fip: $n changed" >&2
    exit 1
  }
done

cp "$work/signed.fip" "$fip.tmp"
mv "$fip.tmp" "$fip"
echo "sign-fip: $fip re-signed${pub:+ (key = $pub)}"

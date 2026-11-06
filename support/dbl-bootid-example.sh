#!/usr/bin/env sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright 2026 Deadband Inc.
#
# Writes board/myd-yf135/dbl-bootid-example.bin as a reference dbl-bootid
# EEPROM image for testing host tools. Signed only with the public test key.
#
#   fsbl, fsbl-prev   build FSBL signed with the test key in all 8 key slots
#                     (image_version 2 and 1)
#   tkc-*, cfg-cert   certificates from the build's stock and consent FIPs
#   deviceid          self-signed device certificate
# Signatures differ on every run: rerun only after a layout change.
#
# Usage: dbl-bootid-example.sh <images dir> <fiptool>
#   <images dir>: a completed build's images/ (FSBL, fip.bin, fip-consent.bin)
set -eu

[ "$#" -eq 2 ] || {
  echo "Usage: $0 <images dir> <fiptool>" >&2
  exit 2
}
images=$1
fiptool=$2
repo=$(cd "$(dirname "$0")/.." && pwd)
key=$repo/board/myd-yf135/insecure-test-key/insecure-tbb-key.pem
tmp=$(mktemp -d)
trap 'rm -rf "${tmp:?}"' EXIT

openssl pkey -in "$key" -pubout -out "$tmp/pub.pem"
fsbl=$(find "$images" -maxdepth 1 -name 'tf-a-*-tf-a.stm32' -print -quit)
for v in 1 2; do
  python3 "$repo/support/stm32-sign.py" sign -k "$key" -v "$v" \
    -p "$tmp/pub.pem" "$tmp/pub.pem" "$tmp/pub.pem" "$tmp/pub.pem" \
    "$tmp/pub.pem" "$tmp/pub.pem" "$tmp/pub.pem" "$tmp/pub.pem" \
    "$fsbl" "$tmp/fsbl-v$v.stm32"
done

mkdir "$tmp/stock" "$tmp/consent"
"$fiptool" unpack --out "$tmp/stock" "$images/fip.bin" >/dev/null
"$fiptool" unpack --out "$tmp/consent" "$images/fip-consent.bin" >/dev/null

openssl req -x509 -new -key "$key" -sha256 -days 36500 -outform DER \
  -subj "/CN=dbl-INSECURE-test-deviceid/serialNumber=TEST0000" \
  -out "$tmp/deviceid.der"

python3 "$repo/board/myd-yf135/dbl-bootid.py" pack "$repo/board/myd-yf135/dbl-bootid.toml" \
  "$repo/board/myd-yf135/dbl-bootid-example.bin" \
  fsbl="$tmp/fsbl-v2.stm32" \
  fsbl-prev="$tmp/fsbl-v1.stm32" \
  tkc-consent="$tmp/consent/trusted-key-cert.bin" \
  tkc-stock="$tmp/stock/trusted-key-cert.bin" \
  cfg-cert="$tmp/stock/stm32mp-cfg-cert.bin" \
  deviceid="$tmp/deviceid.der"

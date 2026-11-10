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
#   deviceid          certificate from insecure-deviceid-ca.crt for the
#                     STM32MP13xD DeviceID key
# Signatures differ on every run: rerun only after a layout change.
#
# USAGE: dbl-bootid-example.sh <images> <fiptool>
#   <images>: images/ dir including FSBL, fip.bin, fip-consent.bin
# /ENDUSAGE
set -eu

usage() {
  sed -n '/^# \/ENDUSAGE/q; /^# USAGE:/,$s/^# \{0,1\}//p' "$0" >&2
  exit 2
}

[ "$#" -eq 2 ] || usage
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

# DeviceID public key of every STM32MP13xD (see package/dbl-tee/src/ta/dbl_include/dbl_key.h)
# Read with `dbl-tee deviceid-pubkey`
d_pubkey=04c05242d8df23fd74ab49638a3e1e73c729d3417adb0d7f737d5cdda7019f38212f2bec9c3e2dc3977ffcd37b1c84665781b8483e24183744380011e08801d908
sh "$repo/support/dbl-deviceid.sh" issue \
  "$repo/board/myd-yf135/insecure-test-key/insecure-deviceid-ca.crt" "$key" \
  "$d_pubkey" "/CN=dbl-INSECURE-test-deviceid/serialNumber=TEST-0000" \
  "$tmp/deviceid.der"

python3 "$repo/board/myd-yf135/dbl-bootid.py" pack "$repo/board/myd-yf135/dbl-bootid.toml" \
  "$repo/board/myd-yf135/dbl-bootid-example.bin" \
  fsbl="$tmp/fsbl-v2.stm32" \
  fsbl-prev="$tmp/fsbl-v1.stm32" \
  tkc-consent="$tmp/consent/trusted-key-cert.bin" \
  tkc-stock="$tmp/stock/trusted-key-cert.bin" \
  cfg-cert="$tmp/stock/stm32mp-cfg-cert.bin" \
  deviceid="$tmp/deviceid.der"

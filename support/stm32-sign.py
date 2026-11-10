#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright 2026 Deadband Inc.
r"""Sign STM32MP13 FSBL images.

Takes a header v2 image from TF-A and writes a signed image matching
STM32_SigningTool_CLI 2.22 (-hv 2 -of 0x1 -t fsbl).

Output differs from the tool's only in the signature (fresh random nonce
each run) and the padding extension (zeroed, not random).

Entry, load address, binary type and payload pass through unchanged.

Usage:
  stm32-sign.py sign [-N <engine>] -k <key> -p <pub0.pem> ... <pub7.pem>
                [-i <pk_idx>] [-v <image_version>] <in.stm32> <out.stm32>
  stm32-sign.py verify [-p <pub0.pem> ... <pub7.pem>] <image.stm32>
  stm32-sign.py pkh <pub0.pem> ... <pub7.pem>

  <key>  PEM file, or with -N an engine key ID (e.g. -N pkcs11 with a pkcs11:
         URI; engine config via OPENSSL_CONF).
  -N     OpenSSL engine for <key>, as mkimage -N.
  -i     slot of <key> in the 8-slot public key table (default 0).
  -v     image_version; the ROM refuses images below OTP CFG4.
  verify checks header, extension flags, payload checksum and signature,
         and that the key at the signing slot matches its hash. With -p
         it also checks the hash table against the given keys.
  pkh    prints the table hash (PKHTH) to fuse into OTP words 24-31.

Layout (offsets in the file; integers little endian):
  Base header, 0x000-0x7f:
   0x00  magic "STM2"
   0x04  ecdsa r||s, 64 bytes
   0x44  payload checksum (byte sum)
   0x48  header_version 0x00020000
   0x4c  image_length
   0x50  entry
   0x58  load
   0x60  image_version
   0x64  extension_flags (bit 0 auth, bit 31 padding)
   0x68  extension_headers_length
   0x6c  binary_type (0x10 = FSBL)
  Auth extension, 0x080-0x1d3:
   0x080  type "ST\0\2"
   0x084  length 0x154
   0x088  pk_idx
   0x08c  nb_pk = 8
   0x090  ecc_algo = 1 (P-256)
   0x094  ecc_pubk X||Y of the signing key, 64 bytes
   0x0d4  pk_hashes[8], 32 bytes each:
          SHA-256(u32 ecc_algo || X || Y)
  Padding extension, 0x1d4-0x1ff:
   0x1d4  type "ST\xff\xff"
   0x1d8  length 0x2c
   0x1dc  zeros (ST fills this with random bytes; both are signed)
  Payload, 0x200 onward: zero padded to a multiple of 32 bytes.
  Signature: ECDSA-SHA256 over 0x48 to end of file.
  PKHTH = SHA-256(pk_hashes[0] || ... || pk_hashes[7]).
"""

import argparse
import hashlib
import os
import struct
import subprocess
import sys
import tempfile

MAGIC = b"STM2"
HEADER_VERSION = 0x00020000
AUTH_TYPE = 0x02005453
PAD_TYPE = 0xFFFF5453
EXT_AUTH = 1 << 0
EXT_PAD = 1 << 31
ALGO_P256 = 1
NB_PK = 8
BASE_LEN = 0x80
EXT_LEN = 0x180
AUTH_LEN = 8 + 12 + 64 + 32 * NB_PK
PAYLOAD_ALIGN = 32
SIG_RANGE = 0x48
# u32 fields from 0x44 (payload checksum) to 0x6c (binary_type)
HEADER_FIELDS = (
    "csum",
    "hver",
    "length",
    "entry",
    "r1",
    "load",
    "r2",
    "version",
    "flags",
    "extlen",
    "btype",
)
# P-256 SubjectPublicKeyInfo DER = this prefix + 0x04 || X || Y.
P256_SPKI_PREFIX = bytes.fromhex("3059301306072a8648ce3d020106082a8648ce3d030107034200")


def die(msg):
    sys.exit(f"stm32-sign: {msg}")


def openssl(*args, data=None):
    try:
        return subprocess.run(
            ["openssl", *args], input=data, capture_output=True, check=True
        ).stdout
    except subprocess.CalledProcessError as e:
        die(f"openssl {args[0]}: {e.stderr.decode().strip()}")


def engine_args(engine, form="-keyform"):
    """Engine key options; openssl pkey names the format option -inform."""
    return ["-engine", engine, form, "engine"] if engine else []


def key_xy(key, public=True, engine=None):
    """X||Y of a P-256 key: public PEM, or private PEM / engine key."""
    if public:
        der = openssl("pkey", "-pubin", "-in", key, "-outform", "DER")
    else:
        der = openssl(
            "pkey",
            *engine_args(engine, "-inform"),
            "-in",
            key,
            "-pubout",
            "-outform",
            "DER",
        )
    if not der.startswith(P256_SPKI_PREFIX + b"\x04") or len(der) != 91:
        die(f"{key}: not a P-256 key")
    return der[-64:]


def pk_hash(xy):
    return hashlib.sha256(struct.pack("<I", ALGO_P256) + xy).digest()


def der_int(buf, pos):
    if buf[pos] != 0x02:
        die("bad DER signature")
    n = buf[pos + 1]
    return int.from_bytes(buf[pos + 2 : pos + 2 + n], "big"), pos + 2 + n


def der_to_rs(der):
    if der[0] != 0x30 or der[1] & 0x80:
        die("bad DER signature")
    r, pos = der_int(der, 2)
    s, _ = der_int(der, pos)
    return r.to_bytes(32, "big") + s.to_bytes(32, "big")


def rs_to_der(rs):
    def enc(v):
        b = v.lstrip(b"\x00") or b"\x00"
        if b[0] & 0x80:
            b = b"\x00" + b
        return b"\x02" + bytes([len(b)]) + b

    body = enc(rs[:32]) + enc(rs[32:])
    return b"\x30" + bytes([len(body)]) + body


def parse_header(img):
    if len(img) < BASE_LEN + EXT_LEN or img[:4] != MAGIC:
        die("not an STM32 image")
    hdr = dict(zip(HEADER_FIELDS, struct.unpack_from("<11I", img, 0x44)))
    if hdr["hver"] != HEADER_VERSION:
        die(f"header version {hdr['hver']:#x}, need {HEADER_VERSION:#x}")
    return hdr


def sign(args):
    pubs = [key_xy(p) for p in args.pub]
    if not 0 <= args.idx < NB_PK:
        die(f"pk_idx {args.idx} out of range")
    if not 0 <= args.version <= 0xFFFFFFFF:
        die(f"image_version {args.version} out of range")
    xy = key_xy(args.key, public=False, engine=args.engine)
    if xy != pubs[args.idx]:
        die(f"key does not match public key {args.idx}")

    src = open(args.input, "rb").read()
    hdr = parse_header(src)
    payload = src[BASE_LEN + hdr["extlen"] :][: hdr["length"]]
    if len(payload) != hdr["length"]:
        die("payload shorter than image_length")
    payload += b"\x00" * (-len(payload) % PAYLOAD_ALIGN)

    auth = struct.pack("<IIIII", AUTH_TYPE, AUTH_LEN, args.idx, NB_PK, ALGO_P256)
    auth += xy + b"".join(pk_hash(p) for p in pubs)
    pad = struct.pack("<II", PAD_TYPE, EXT_LEN - AUTH_LEN)
    pad += b"\x00" * (EXT_LEN - AUTH_LEN - 8)
    base = MAGIC + b"\x00" * 64
    base += struct.pack(
        "<11I",
        sum(payload) & 0xFFFFFFFF,
        HEADER_VERSION,
        len(payload),
        hdr["entry"],
        0,
        hdr["load"],
        0,
        args.version,
        EXT_AUTH | EXT_PAD,
        EXT_LEN,
        hdr["btype"],
    )
    base += b"\x00" * (BASE_LEN - len(base))
    img = bytearray(base + auth + pad + payload)

    digest = hashlib.sha256(img[SIG_RANGE:]).digest()
    der = openssl(
        "pkeyutl",
        "-sign",
        *engine_args(args.engine),
        "-inkey",
        args.key,
        "-pkeyopt",
        "digest:sha256",
        data=digest,
    )
    img[4:68] = der_to_rs(der)
    check(bytes(img), pubs)
    with open(args.output, "wb") as out:
        out.write(img)


def check(img, pubs=None):
    """Raise on any mismatch; returns PKHTH."""
    hdr = parse_header(img)
    if hdr["flags"] != EXT_AUTH | EXT_PAD or hdr["extlen"] != EXT_LEN:
        die(f"extension flags {hdr['flags']:#x}: no authentication extension")
    typ, length, idx, nb, algo = struct.unpack_from("<IIIII", img, BASE_LEN)
    if (typ, length, nb, algo) != (AUTH_TYPE, AUTH_LEN, NB_PK, ALGO_P256):
        die("bad authentication extension")
    if idx >= NB_PK:
        die(f"pk_idx {idx} out of range")
    xy = img[BASE_LEN + 20 : BASE_LEN + 84]
    table = [img[BASE_LEN + 84 + 32 * i :][:32] for i in range(NB_PK)]
    if pk_hash(xy) != table[idx]:
        die(f"ecc_pubk does not match pk_hashes[{idx}]")
    if pubs and [pk_hash(p) for p in pubs] != table:
        die("pk_hashes differ from the given public keys")
    payload = img[BASE_LEN + EXT_LEN :]
    if len(payload) != hdr["length"] or sum(payload) & 0xFFFFFFFF != hdr["csum"]:
        die("payload length or checksum mismatch")

    with tempfile.TemporaryDirectory() as tmp:
        pem = os.path.join(tmp, "pub.der")
        sig = os.path.join(tmp, "sig.der")
        dig = os.path.join(tmp, "digest")
        open(pem, "wb").write(P256_SPKI_PREFIX + b"\x04" + xy)
        open(sig, "wb").write(rs_to_der(img[4:68]))
        open(dig, "wb").write(hashlib.sha256(img[SIG_RANGE:]).digest())
        r = subprocess.run(
            [
                "openssl",
                "pkeyutl",
                "-verify",
                "-pubin",
                "-keyform",
                "DER",
                "-inkey",
                pem,
                "-sigfile",
                sig,
                "-in",
                dig,
                "-pkeyopt",
                "digest:sha256",
            ],
            capture_output=True,
        )
        if r.returncode:
            die("signature invalid")
    return idx, hdr["version"], hashlib.sha256(b"".join(table)).hexdigest()


def verify(args):
    pubs = [key_xy(p) for p in args.pub] if args.pub else None
    idx, version, pkhth = check(open(args.image, "rb").read(), pubs)
    print(f"OK pk_idx={idx} image_version={version} PKHTH={pkhth}")


def pkh(args):
    table = b"".join(pk_hash(key_xy(p)) for p in args.pub)
    print(hashlib.sha256(table).hexdigest())


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("sign")
    s.add_argument("-N", "--engine")
    s.add_argument("-k", "--key", required=True)
    s.add_argument("-p", "--pub", nargs=NB_PK, required=True)
    s.add_argument("-i", "--idx", type=int, default=0)
    s.add_argument("-v", "--version", type=int, default=0)
    s.add_argument("input")
    s.add_argument("output")
    s.set_defaults(func=sign)
    v = sub.add_parser("verify")
    v.add_argument("-p", "--pub", nargs=NB_PK)
    v.add_argument("image")
    v.set_defaults(func=verify)
    h = sub.add_parser("pkh")
    h.add_argument("pub", nargs=NB_PK)
    h.set_defaults(func=pkh)
    args = ap.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()

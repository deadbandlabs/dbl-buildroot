/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Copyright 2026 Deadband Inc. */
/*
 * Early TA interface, shared by the TAs and the dbl-tee CLI.
 * UUIDs are permanent: the DeviceID key is derived from the TA's UUID.
 * Each UUID is repeated in the TA's user_ta.mk.
 */
#ifndef DBL_TEE_H
#define DBL_TEE_H

/* df5c8c94-779b-4c86-a5de-cb22935a0886 */
#define DBL_CONSENT_UUID { 0xdf5c8c94, 0x779b, 0x4c86, \
		{ 0xa5, 0xde, 0xcb, 0x22, 0x93, 0x5a, 0x08, 0x86 } }

/*
 * Build mode of the running OP-TEE
 * [out] value[0].a  DBL_MODE_*
 */
#define DBL_CONSENT_CMD_GET_MODE	0

#define DBL_MODE_STOCK			0
#define DBL_MODE_CONSENT		1

/* b691878d-2e1e-4fac-9af0-836ee6a92d34 */
#define DBL_DEVICEID_UUID { 0xb691878d, 0x2e1e, 0x4fac, \
		{ 0x9a, 0xf0, 0x83, 0x6e, 0xe6, 0xa9, 0x2d, 0x34 } }

/*
 * DeviceID public key, P-256, SEC1 uncompressed (0x04 || X || Y)
 * [out] memref[0]  DBL_DEVICEID_PUBKEY_SIZE bytes
 */
#define DBL_DEVICEID_CMD_GET_PUBKEY	0

/*
 * ECDSA P-256 signature over SHA-256(DBL_ATTEST_PREFIX || nonce)
 * [in]  memref[0]  nonce, 1..DBL_ATTEST_NONCE_MAX bytes
 * [out] memref[1]  r || s, DBL_DEVICEID_SIG_SIZE bytes
 */
#define DBL_DEVICEID_CMD_ATTEST		1

#define DBL_DEVICEID_PUBKEY_SIZE	65
#define DBL_DEVICEID_SIG_SIZE		64
#define DBL_ATTEST_PREFIX		"dbl-attest-v1"
#define DBL_ATTEST_NONCE_MAX		64

/*
 * Unit keys: eight P-256 keys (slots) for STM32 ROM public key table
 * Consent build only (BR2_PACKAGE_DBL_CONSENT_BOOT)
 */
/* f0a3fe84-5a1e-4d3c-89d3-65cf6b1b0b7e */
#define DBL_UNITKEY_UUID { 0xf0a3fe84, 0x5a1e, 0x4d3c, \
		{ 0x89, 0xd3, 0x65, 0xcf, 0x6b, 0x1b, 0x0b, 0x7e } }

#define DBL_UNITKEY_SLOTS		8

/*
 * Public keys X || Y of all slots, in slot order
 * [out] memref[0]  DBL_UNITKEY_SLOTS * 64 bytes
 */
#define DBL_UNITKEY_CMD_GET_PUBKEYS	0

/*
 * Signs an FSBL for the ROM: STM32 header v2 with the authentication
 * extension (pk_idx, the slot's public key, hashes of all slot keys).
 * Payload, entry, load address and binary type come from the input image.
 * [in]  value[0].a  pk_idx (slot)
 * [in]  value[0].b  image_version
 * [in]  memref[1]   STM32 image (header v2)
 * [out] memref[2]   signed image, DBL_FSBL_HEADER_SIZE + padded payload
 */
#define DBL_UNITKEY_CMD_SIGN_FSBL	1

#define DBL_FSBL_HEADER_SIZE		0x200
#define DBL_FSBL_MAX			(512 * 1024)

/*
 * TF-A Trusted Key Certificate (TBBR), self-signed by a slot key
 * [in]  value[0].a  slot
 * [in]  memref[1]   trusted world public key, SEC1 uncompressed (65 bytes)
 * [in]  memref[2]   non-trusted world public key, SEC1 uncompressed
 * [out] memref[3]   DER certificate, at most DBL_CERT_MAX bytes
 */
#define DBL_UNITKEY_CMD_SIGN_TKC	2

/*
 * TF-A STM32MP config certificate (TBBR root, covers fw_config), self-signed
 * by a slot key. hw_config hash is zero (not used).
 * [in]  value[0].a  slot
 * [in]  memref[1]   SHA-256 of fw_config (32 bytes)
 * [out] memref[2]   DER certificate, at most DBL_CERT_MAX bytes
 */
#define DBL_UNITKEY_CMD_SIGN_CFG	3

#define DBL_CERT_MAX			1024

#endif /* DBL_TEE_H */

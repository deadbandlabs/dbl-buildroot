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

#endif /* DBL_TEE_H */

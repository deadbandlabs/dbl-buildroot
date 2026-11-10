/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Copyright 2026 Deadband Inc. */
/*
 * P-256 keys derived from the hardware unique key (HUK) and the calling TA's
 * UUID (PTA_SYSTEM_DERIVE_TA_UNIQUE_KEY), recomputed on every use.
 *
 * Derivation input: label || counter. The first counter value whose output is
 * a valid scalar (1 <= d < n) is the key. Changing a label, the counter
 * encoding or the UUID changes the key on every device.
 *
 * Header-only: each TA links its own copy.
 */
#ifndef DBL_KEY_H
#define DBL_KEY_H

#include <mbedtls/ecdsa.h>
#include <mbedtls/ecp.h>
#include <pta_system.h>
#include <string.h>
#include <string_ext.h>
#include <tee_internal_api.h>

#define DBL_KEY_SCALAR_SIZE	32
#define DBL_KEY_LABEL_MAX	32
/* Retries for an invalid scalar (probability ~2^-32 each) */
#define DBL_KEY_MAX_TRIES	8

static inline int dbl_key_rng(void *ctx __unused, unsigned char *buf,
			      size_t len)
{
	TEE_GenerateRandom(buf, len);
	return 0;
}

static inline TEE_Result dbl_key_derive(const uint8_t *label,
					size_t label_len, uint8_t counter,
					uint8_t *out)
{
	static const TEE_UUID system_uuid = PTA_SYSTEM_UUID;
	uint8_t extra[DBL_KEY_LABEL_MAX + 1] = { };
	TEE_TASessionHandle sess = TEE_HANDLE_NULL;
	TEE_Param params[TEE_NUM_PARAMS] = { };
	uint32_t pt = TEE_PARAM_TYPES(TEE_PARAM_TYPE_MEMREF_INPUT,
				      TEE_PARAM_TYPE_MEMREF_OUTPUT,
				      TEE_PARAM_TYPE_NONE,
				      TEE_PARAM_TYPE_NONE);
	uint32_t origin = 0;
	TEE_Result res = TEE_ERROR_GENERIC;

	if (label_len > DBL_KEY_LABEL_MAX)
		return TEE_ERROR_BAD_PARAMETERS;
	memcpy(extra, label, label_len);
	extra[label_len] = counter;

	res = TEE_OpenTASession(&system_uuid, TEE_TIMEOUT_INFINITE, 0, NULL,
				&sess, &origin);
	if (res)
		return res;

	params[0].memref.buffer = extra;
	params[0].memref.size = label_len + 1;
	params[1].memref.buffer = out;
	params[1].memref.size = DBL_KEY_SCALAR_SIZE;
	res = TEE_InvokeTACommand(sess, TEE_TIMEOUT_INFINITE,
				  PTA_SYSTEM_DERIVE_TA_UNIQUE_KEY, pt, params,
				  &origin);
	TEE_CloseTASession(sess);
	return res;
}

/* Loads the private key for label and computes its public key */
static inline TEE_Result dbl_key_load(const uint8_t *label, size_t label_len,
				      mbedtls_ecp_keypair *kp)
{
	uint8_t d[DBL_KEY_SCALAR_SIZE] = { };
	TEE_Result res = TEE_ERROR_GENERIC;
	int ret = 0;
	uint8_t i = 0;

	for (i = 0; i < DBL_KEY_MAX_TRIES; i++) {
		res = dbl_key_derive(label, label_len, i, d);
		if (res)
			goto out;
		/* Rejects d = 0 and d >= n */
		ret = mbedtls_ecp_read_key(MBEDTLS_ECP_DP_SECP256R1, kp, d,
					   sizeof(d));
		if (ret != MBEDTLS_ERR_ECP_INVALID_KEY)
			break;
	}
	if (i == DBL_KEY_MAX_TRIES || ret) {
		res = TEE_ERROR_GENERIC;
		goto out;
	}

	if (mbedtls_ecp_keypair_calc_public(kp, dbl_key_rng, NULL))
		res = TEE_ERROR_GENERIC;
out:
	memzero_explicit(d, sizeof(d));
	return res;
}

/* X || Y, 64 bytes */
static inline TEE_Result dbl_key_xy(const mbedtls_ecp_keypair *kp,
				    uint8_t xy[64])
{
	uint8_t pt[65] = { };
	size_t olen = 0;

	if (mbedtls_ecp_write_public_key(kp, MBEDTLS_ECP_PF_UNCOMPRESSED,
					 &olen, pt, sizeof(pt)) ||
	    olen != sizeof(pt))
		return TEE_ERROR_GENERIC;
	memcpy(xy, pt + 1, 64);
	return TEE_SUCCESS;
}

/* ECDSA over a SHA-256 digest, random k; raw r || s, 64 bytes */
static inline TEE_Result dbl_key_sign(mbedtls_ecp_keypair *kp,
				      const uint8_t hash[32], uint8_t rs[64])
{
	mbedtls_mpi r;
	mbedtls_mpi s;
	TEE_Result res = TEE_SUCCESS;

	mbedtls_mpi_init(&r);
	mbedtls_mpi_init(&s);
	if (mbedtls_ecdsa_sign(&kp->MBEDTLS_PRIVATE(grp), &r, &s,
			       &kp->MBEDTLS_PRIVATE(d), hash, 32,
			       dbl_key_rng, NULL) ||
	    mbedtls_mpi_write_binary(&r, rs, 32) ||
	    mbedtls_mpi_write_binary(&s, rs + 32, 32))
		res = TEE_ERROR_GENERIC;
	mbedtls_mpi_free(&r);
	mbedtls_mpi_free(&s);
	return res;
}

#endif /* DBL_KEY_H */

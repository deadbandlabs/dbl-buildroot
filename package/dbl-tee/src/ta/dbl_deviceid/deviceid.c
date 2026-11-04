// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright 2026 Deadband Inc.
/*
 * DeviceID: one P-256 key per chip, derived from the hardware unique key
 * (HUK) and this TA's UUID on every use.
 * Signs only attestation challenges: DBL_ATTEST_PREFIX || nonce.
 *
 * Requires hardware SAES. On STM32MP13xD OP-TEE derives from an all-zero HUK:
 * every such device has the same, publicly computable key.
 *
 * Changing DERIVE_LABEL, the UUID or the derivation changes every device's key.
 */
#include <dbl_tee.h>
#include <mbedtls/ecdsa.h>
#include <mbedtls/ecp.h>
#include <mbedtls/sha256.h>
#include <pta_system.h>
#include <string.h>
#include <string_ext.h>
#include <tee_internal_api.h>

#define DERIVE_LABEL	"dbl-deviceid-v1"
#define SCALAR_SIZE	32
/* Retries for a derived value outside [1, n-1] (probability ~2^-32 each) */
#define MAX_TRIES	8

static int rng(void *ctx __unused, unsigned char *buf, size_t len)
{
	TEE_GenerateRandom(buf, len);
	return 0;
}

static TEE_Result derive(uint8_t counter, uint8_t *out)
{
	static const TEE_UUID system_uuid = PTA_SYSTEM_UUID;
	uint8_t extra[sizeof(DERIVE_LABEL)] = DERIVE_LABEL;
	TEE_TASessionHandle sess = TEE_HANDLE_NULL;
	TEE_Param params[TEE_NUM_PARAMS] = { };
	uint32_t pt = TEE_PARAM_TYPES(TEE_PARAM_TYPE_MEMREF_INPUT,
				      TEE_PARAM_TYPE_MEMREF_OUTPUT,
				      TEE_PARAM_TYPE_NONE,
				      TEE_PARAM_TYPE_NONE);
	uint32_t origin = 0;
	TEE_Result res = TEE_ERROR_GENERIC;

	/* Label's NUL is replaced by the counter */
	extra[sizeof(extra) - 1] = counter;

	res = TEE_OpenTASession(&system_uuid, TEE_TIMEOUT_INFINITE, 0, NULL,
				&sess, &origin);
	if (res)
		return res;

	params[0].memref.buffer = extra;
	params[0].memref.size = sizeof(extra);
	params[1].memref.buffer = out;
	params[1].memref.size = SCALAR_SIZE;
	res = TEE_InvokeTACommand(sess, TEE_TIMEOUT_INFINITE,
				  PTA_SYSTEM_DERIVE_TA_UNIQUE_KEY, pt, params,
				  &origin);
	TEE_CloseTASession(sess);
	return res;
}

/* Loads the DeviceID private key and computes its public key */
static TEE_Result load_key(mbedtls_ecp_keypair *kp)
{
	uint8_t d[SCALAR_SIZE] = { };
	TEE_Result res = TEE_ERROR_GENERIC;
	int ret = 0;
	uint8_t i = 0;

	for (i = 0; i < MAX_TRIES; i++) {
		res = derive(i, d);
		if (res)
			goto out;
		/* Rejects d = 0 and d >= n */
		ret = mbedtls_ecp_read_key(MBEDTLS_ECP_DP_SECP256R1, kp, d,
					   sizeof(d));
		if (ret != MBEDTLS_ERR_ECP_INVALID_KEY)
			break;
	}
	if (i == MAX_TRIES || ret) {
		res = TEE_ERROR_GENERIC;
		goto out;
	}

	if (mbedtls_ecp_keypair_calc_public(kp, rng, NULL))
		res = TEE_ERROR_GENERIC;
out:
	memzero_explicit(d, sizeof(d));
	return res;
}

static TEE_Result get_pubkey(uint32_t pt, TEE_Param params[TEE_NUM_PARAMS])
{
	mbedtls_ecp_keypair kp;
	TEE_Result res = TEE_ERROR_GENERIC;
	size_t olen = 0;

	if (pt != TEE_PARAM_TYPES(TEE_PARAM_TYPE_MEMREF_OUTPUT,
				  TEE_PARAM_TYPE_NONE,
				  TEE_PARAM_TYPE_NONE,
				  TEE_PARAM_TYPE_NONE))
		return TEE_ERROR_BAD_PARAMETERS;
	if (params[0].memref.size < DBL_DEVICEID_PUBKEY_SIZE) {
		params[0].memref.size = DBL_DEVICEID_PUBKEY_SIZE;
		return TEE_ERROR_SHORT_BUFFER;
	}

	mbedtls_ecp_keypair_init(&kp);
	res = load_key(&kp);
	if (res)
		goto out;
	if (mbedtls_ecp_write_public_key(&kp, MBEDTLS_ECP_PF_UNCOMPRESSED,
					 &olen, params[0].memref.buffer,
					 params[0].memref.size) ||
	    olen != DBL_DEVICEID_PUBKEY_SIZE) {
		res = TEE_ERROR_GENERIC;
		goto out;
	}
	params[0].memref.size = olen;
out:
	mbedtls_ecp_keypair_free(&kp);
	return res;
}

static TEE_Result attest(uint32_t pt, TEE_Param params[TEE_NUM_PARAMS])
{
	uint8_t msg[sizeof(DBL_ATTEST_PREFIX) - 1 + DBL_ATTEST_NONCE_MAX] = { };
	size_t prefix_len = sizeof(DBL_ATTEST_PREFIX) - 1;
	size_t nonce_len = 0;
	uint8_t hash[32] = { };
	uint8_t sig[DBL_DEVICEID_SIG_SIZE] = { };
	mbedtls_ecp_keypair kp;
	mbedtls_mpi r;
	mbedtls_mpi s;
	TEE_Result res = TEE_ERROR_GENERIC;

	if (pt != TEE_PARAM_TYPES(TEE_PARAM_TYPE_MEMREF_INPUT,
				  TEE_PARAM_TYPE_MEMREF_OUTPUT,
				  TEE_PARAM_TYPE_NONE,
				  TEE_PARAM_TYPE_NONE))
		return TEE_ERROR_BAD_PARAMETERS;
	nonce_len = params[0].memref.size;
	if (!nonce_len || nonce_len > DBL_ATTEST_NONCE_MAX)
		return TEE_ERROR_BAD_PARAMETERS;
	if (params[1].memref.size < DBL_DEVICEID_SIG_SIZE) {
		params[1].memref.size = DBL_DEVICEID_SIG_SIZE;
		return TEE_ERROR_SHORT_BUFFER;
	}

	/* Copy first: the nonce sits in memory the client can change */
	memcpy(msg, DBL_ATTEST_PREFIX, prefix_len);
	memcpy(msg + prefix_len, params[0].memref.buffer, nonce_len);
	if (mbedtls_sha256(msg, prefix_len + nonce_len, hash, 0))
		return TEE_ERROR_GENERIC;

	mbedtls_ecp_keypair_init(&kp);
	mbedtls_mpi_init(&r);
	mbedtls_mpi_init(&s);
	res = load_key(&kp);
	if (res)
		goto out;
	if (mbedtls_ecdsa_sign(&kp.MBEDTLS_PRIVATE(grp), &r, &s,
			       &kp.MBEDTLS_PRIVATE(d), hash, sizeof(hash),
			       rng, NULL) ||
	    mbedtls_mpi_write_binary(&r, sig, 32) ||
	    mbedtls_mpi_write_binary(&s, sig + 32, 32)) {
		res = TEE_ERROR_GENERIC;
		goto out;
	}
	memcpy(params[1].memref.buffer, sig, sizeof(sig));
	params[1].memref.size = sizeof(sig);
out:
	mbedtls_mpi_free(&r);
	mbedtls_mpi_free(&s);
	mbedtls_ecp_keypair_free(&kp);
	return res;
}

TEE_Result TA_CreateEntryPoint(void)
{
	return TEE_SUCCESS;
}

void TA_DestroyEntryPoint(void)
{
}

TEE_Result TA_OpenSessionEntryPoint(uint32_t param_types __unused,
				    TEE_Param params[TEE_NUM_PARAMS] __unused,
				    void **sess_ctx __unused)
{
	return TEE_SUCCESS;
}

void TA_CloseSessionEntryPoint(void *sess_ctx __unused)
{
}

TEE_Result TA_InvokeCommandEntryPoint(void *sess_ctx __unused, uint32_t cmd,
				      uint32_t param_types,
				      TEE_Param params[TEE_NUM_PARAMS])
{
	switch (cmd) {
	case DBL_DEVICEID_CMD_GET_PUBKEY:
		return get_pubkey(param_types, params);
	case DBL_DEVICEID_CMD_ATTEST:
		return attest(param_types, params);
	default:
		return TEE_ERROR_NOT_SUPPORTED;
	}
}

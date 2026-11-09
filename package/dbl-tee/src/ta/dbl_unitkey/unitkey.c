// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright 2026 Deadband Inc.
/*
 * Unit keys: eight P-256 keys (slots 0-7) per chip, derived from the hardware
 * unique key (dbl_key.h). Their hashes form the STM32 ROM public key table.
 * A slot key signs FSBLs (ROM check) and the two TF-A root certificates
 * (trusted key certificate, STM32MP config certificate).
 *
 * Built only into the consent OP-TEE.
 *
 * The caller picks pk_idx and image_version; the ROM revokes all lower slots
 * and raises its version counter when it boots the result (per UM2885).
 *
 * Requires hardware SAES. On STM32MP13xD OP-TEE derives from an all-zero HUK:
 * every such device has the same, publicly computable keys.
 *
 * Changing DERIVE_LABEL or the UUID changes every device's keys.
 */
#include <dbl_key.h>
#include <dbl_tee.h>
#include <mbedtls/oid.h>
#include <mbedtls/pk.h>
#include <mbedtls/sha256.h>
#include <mbedtls/x509_crt.h>
#include <string.h>
#include <tee_internal_api.h>
#include <util.h>

/* Derivation input: label || slot || counter (dbl_key.h adds the counter) */
#define DERIVE_LABEL	"dbl-unitkey-v1"

/* STM32 header v2 (support/stm32-sign.py documents the layout) */
#define HDR_MAGIC		"STM2"
#define HDR_VERSION		0x00020000
#define HDR_BASE_LEN		0x80
#define HDR_EXT_LEN		0x180
#define HDR_SIG_RANGE		0x48
#define HDR_EXT_AUTH		(1U << 0)
#define HDR_EXT_PAD		(1U << 31)
#define AUTH_TYPE		0x02005453
#define PAD_TYPE		0xFFFF5453
#define ALGO_P256		1
#define AUTH_LEN		(8 + 12 + 64 + 32 * DBL_UNITKEY_SLOTS)
#define PAYLOAD_ALIGN		32

/* TBBR OIDs (TF-A include/tools_share/tbbr_oid.h) */
#define OID_TFW_NVCOUNTER	"\x2b\x06\x01\x04\x01\xa0\x20\x90\x34\x01"
#define OID_TRUSTED_WORLD_PK	"\x2b\x06\x01\x04\x01\xa0\x20\x90\x34\x82\x2e"
#define OID_NON_TRUSTED_WORLD_PK "\x2b\x06\x01\x04\x01\xa0\x20\x90\x34\x82\x2f"
#define OID_HW_CONFIG_HASH	"\x2b\x06\x01\x04\x01\xa0\x20\x90\x34\x81\x4b"
#define OID_FW_CONFIG_HASH	"\x2b\x06\x01\x04\x01\xa0\x20\x90\x34\x81\x4c"
#define TKC_CN			"CN=Trusted Key Certificate"
/* STM32MP config certificate (TF-A plat/st/stm32mp1/stm32mp1_tbb_cert.c) */
#define CFG_CN			"CN=STM32MP config FW Certificate"
/* Fixed validity, not checked by TF-A */
#define CERT_NOT_BEFORE		"20260101000000"
#define CERT_NOT_AFTER		"20460101000000"
/* DigestInfo DER of a SHA-256 hash: 19-byte prefix + hash */
#define DIGEST_INFO_LEN		51
/* SubjectPublicKeyInfo DER of a P-256 key: 91 bytes */
#define SPKI_P256_LEN		91

static TEE_Result load_slot(uint32_t slot, mbedtls_ecp_keypair *kp)
{
	uint8_t label[sizeof(DERIVE_LABEL)] = DERIVE_LABEL;

	if (slot >= DBL_UNITKEY_SLOTS)
		return TEE_ERROR_BAD_PARAMETERS;
	/* Label's NUL is replaced by the slot */
	label[sizeof(label) - 1] = slot;
	return dbl_key_load(label, sizeof(label), kp);
}

static TEE_Result slot_xy(uint32_t slot, uint8_t xy[64])
{
	mbedtls_ecp_keypair kp;
	TEE_Result res = TEE_ERROR_GENERIC;

	mbedtls_ecp_keypair_init(&kp);
	res = load_slot(slot, &kp);
	if (!res)
		res = dbl_key_xy(&kp, xy);
	mbedtls_ecp_keypair_free(&kp);
	return res;
}

static void put_u32(uint8_t *p, uint32_t v)
{
	p[0] = v;
	p[1] = v >> 8;
	p[2] = v >> 16;
	p[3] = v >> 24;
}

static uint32_t get_u32(const uint8_t *p)
{
	return p[0] | (p[1] << 8) | (p[2] << 16) | ((uint32_t)p[3] << 24);
}

static TEE_Result get_pubkeys(uint32_t pt, TEE_Param params[TEE_NUM_PARAMS])
{
	uint8_t xy[DBL_UNITKEY_SLOTS][64] = { };
	TEE_Result res = TEE_ERROR_GENERIC;
	uint32_t i = 0;

	if (pt != TEE_PARAM_TYPES(TEE_PARAM_TYPE_MEMREF_OUTPUT,
				  TEE_PARAM_TYPE_NONE,
				  TEE_PARAM_TYPE_NONE,
				  TEE_PARAM_TYPE_NONE))
		return TEE_ERROR_BAD_PARAMETERS;
	if (params[0].memref.size < sizeof(xy)) {
		params[0].memref.size = sizeof(xy);
		return TEE_ERROR_SHORT_BUFFER;
	}

	for (i = 0; i < DBL_UNITKEY_SLOTS; i++) {
		res = slot_xy(i, xy[i]);
		if (res)
			return res;
	}
	memcpy(params[0].memref.buffer, xy, sizeof(xy));
	params[0].memref.size = sizeof(xy);
	return TEE_SUCCESS;
}

/* Writes the 512-byte header at img; payload already at img + 0x200 */
static TEE_Result fsbl_header(uint8_t *img, size_t payload_len,
			      uint32_t pk_idx, uint32_t version,
			      uint32_t entry, uint32_t load, uint32_t btype,
			      const uint8_t xy_all[DBL_UNITKEY_SLOTS][64])
{
	uint8_t *auth = img + HDR_BASE_LEN;
	uint8_t *pad = auth + AUTH_LEN;
	uint8_t algo[4] = { };
	uint32_t csum = 0;
	size_t i = 0;

	memset(img, 0, DBL_FSBL_HEADER_SIZE);
	for (i = 0; i < payload_len; i++)
		csum += img[DBL_FSBL_HEADER_SIZE + i];

	memcpy(img, HDR_MAGIC, 4);
	put_u32(img + 0x44, csum);
	put_u32(img + 0x48, HDR_VERSION);
	put_u32(img + 0x4c, payload_len);
	put_u32(img + 0x50, entry);
	put_u32(img + 0x58, load);
	put_u32(img + 0x60, version);
	put_u32(img + 0x64, HDR_EXT_AUTH | HDR_EXT_PAD);
	put_u32(img + 0x68, HDR_EXT_LEN);
	put_u32(img + 0x6c, btype);

	put_u32(auth, AUTH_TYPE);
	put_u32(auth + 4, AUTH_LEN);
	put_u32(auth + 8, pk_idx);
	put_u32(auth + 12, DBL_UNITKEY_SLOTS);
	put_u32(auth + 16, ALGO_P256);
	memcpy(auth + 20, xy_all[pk_idx], 64);
	/* pk_hashes[i] = SHA-256(u32 algo || X || Y) */
	put_u32(algo, ALGO_P256);
	for (i = 0; i < DBL_UNITKEY_SLOTS; i++) {
		mbedtls_sha256_context sha;
		int ret = 0;

		mbedtls_sha256_init(&sha);
		ret = mbedtls_sha256_starts(&sha, 0) ||
		      mbedtls_sha256_update(&sha, algo, sizeof(algo)) ||
		      mbedtls_sha256_update(&sha, xy_all[i], 64) ||
		      mbedtls_sha256_finish(&sha, auth + 84 + 32 * i);
		mbedtls_sha256_free(&sha);
		if (ret)
			return TEE_ERROR_GENERIC;
	}

	put_u32(pad, PAD_TYPE);
	put_u32(pad + 4, HDR_EXT_LEN - AUTH_LEN);
	return TEE_SUCCESS;
}

static TEE_Result sign_fsbl(uint32_t pt, TEE_Param params[TEE_NUM_PARAMS])
{
	uint8_t xy_all[DBL_UNITKEY_SLOTS][64] = { };
	uint8_t hash[32] = { };
	mbedtls_ecp_keypair kp;
	const uint8_t *in = NULL;
	size_t in_len = 0;
	uint32_t pk_idx = 0;
	uint32_t version = 0;
	uint32_t entry = 0;
	uint32_t load = 0;
	uint32_t btype = 0;
	uint32_t extlen = 0;
	size_t payload_len = 0;
	size_t padded_len = 0;
	size_t out_len = 0;
	uint8_t *img = NULL;
	TEE_Result res = TEE_ERROR_GENERIC;
	uint32_t i = 0;

	if (pt != TEE_PARAM_TYPES(TEE_PARAM_TYPE_VALUE_INPUT,
				  TEE_PARAM_TYPE_MEMREF_INPUT,
				  TEE_PARAM_TYPE_MEMREF_OUTPUT,
				  TEE_PARAM_TYPE_NONE))
		return TEE_ERROR_BAD_PARAMETERS;
	in = params[1].memref.buffer;
	in_len = params[1].memref.size;
	pk_idx = params[0].value.a;
	version = params[0].value.b;
	if (pk_idx >= DBL_UNITKEY_SLOTS || in_len < DBL_FSBL_HEADER_SIZE ||
	    in_len > DBL_FSBL_MAX)
		return TEE_ERROR_BAD_PARAMETERS;

	/* Copy first: the client can change shared memory at any time */
	img = TEE_Malloc(DBL_FSBL_MAX + PAYLOAD_ALIGN, TEE_MALLOC_FILL_ZERO);
	if (!img)
		return TEE_ERROR_OUT_OF_MEMORY;
	memcpy(img, in, in_len);

	if (memcmp(img, HDR_MAGIC, 4) || get_u32(img + 0x48) != HDR_VERSION) {
		res = TEE_ERROR_BAD_FORMAT;
		goto out;
	}
	payload_len = get_u32(img + 0x4c);
	entry = get_u32(img + 0x50);
	load = get_u32(img + 0x58);
	extlen = get_u32(img + 0x68);
	btype = get_u32(img + 0x6c);
	if (extlen != HDR_EXT_LEN ||
	    payload_len > in_len - DBL_FSBL_HEADER_SIZE) {
		res = TEE_ERROR_BAD_FORMAT;
		goto out;
	}
	/* Zero padding past the payload (bytes from the input are dropped) */
	padded_len = ROUNDUP(payload_len, PAYLOAD_ALIGN);
	memset(img + DBL_FSBL_HEADER_SIZE + payload_len, 0,
	       padded_len - payload_len);
	out_len = DBL_FSBL_HEADER_SIZE + padded_len;
	if (params[2].memref.size < out_len) {
		params[2].memref.size = out_len;
		res = TEE_ERROR_SHORT_BUFFER;
		goto out;
	}

	for (i = 0; i < DBL_UNITKEY_SLOTS; i++) {
		res = slot_xy(i, xy_all[i]);
		if (res)
			goto out;
	}
	res = fsbl_header(img, padded_len, pk_idx, version, entry, load, btype,
			  xy_all);
	if (res)
		goto out;

	if (mbedtls_sha256(img + HDR_SIG_RANGE, out_len - HDR_SIG_RANGE, hash,
			   0)) {
		res = TEE_ERROR_GENERIC;
		goto out;
	}
	mbedtls_ecp_keypair_init(&kp);
	res = load_slot(pk_idx, &kp);
	if (!res)
		res = dbl_key_sign(&kp, hash, img + 4);
	mbedtls_ecp_keypair_free(&kp);
	if (res)
		goto out;

	memcpy(params[2].memref.buffer, img, out_len);
	params[2].memref.size = out_len;
out:
	TEE_Free(img);
	return res;
}

/* SubjectPublicKeyInfo DER of a SEC1 uncompressed P-256 point, checked */
static TEE_Result world_spki(const void *pt, size_t len,
			     uint8_t spki[SPKI_P256_LEN])
{
	mbedtls_ecp_keypair kp;
	mbedtls_pk_context pk;
	uint8_t buf[65] = { };
	TEE_Result res = TEE_ERROR_GENERIC;

	if (len != sizeof(buf))
		return TEE_ERROR_BAD_PARAMETERS;
	memcpy(buf, pt, len);

	mbedtls_ecp_keypair_init(&kp);
	mbedtls_pk_init(&pk);
	if (mbedtls_ecp_group_load(&kp.MBEDTLS_PRIVATE(grp),
				   MBEDTLS_ECP_DP_SECP256R1))
		goto out;
	if (mbedtls_ecp_point_read_binary(&kp.MBEDTLS_PRIVATE(grp),
					  &kp.MBEDTLS_PRIVATE(Q), buf,
					  sizeof(buf)) ||
	    mbedtls_ecp_check_pubkey(&kp.MBEDTLS_PRIVATE(grp),
				     &kp.MBEDTLS_PRIVATE(Q))) {
		res = TEE_ERROR_BAD_PARAMETERS;
		goto out;
	}
	/* mbedtls_pk_write_pubkey_der writes at the end of the buffer */
	if (mbedtls_pk_setup(&pk,
			     mbedtls_pk_info_from_type(MBEDTLS_PK_ECKEY)) ||
	    mbedtls_ecp_copy(&mbedtls_pk_ec(pk)->MBEDTLS_PRIVATE(Q),
			     &kp.MBEDTLS_PRIVATE(Q)) ||
	    mbedtls_ecp_group_copy(&mbedtls_pk_ec(pk)->MBEDTLS_PRIVATE(grp),
				   &kp.MBEDTLS_PRIVATE(grp)) ||
	    mbedtls_pk_write_pubkey_der(&pk, spki, SPKI_P256_LEN) !=
	    SPKI_P256_LEN)
		goto out;
	res = TEE_SUCCESS;
out:
	mbedtls_pk_free(&pk);
	mbedtls_ecp_keypair_free(&kp);
	return res;
}

/* One critical TBBR extension */
struct tbb_ext {
	const char *oid;
	size_t oid_len;
	const uint8_t *val;
	size_t val_len;
};

/*
 * Self-signed TBBR root certificate (cert_create layout): issuer = subject =
 * cn, slot key, NV counter 0 plus exts, DER to out (at most DBL_CERT_MAX)
 */
static TEE_Result root_cert(uint32_t slot, const char *cn,
			    const struct tbb_ext *exts, size_t n_ext,
			    TEE_Param *out)
{
	/* TrustedWorldNVCounter: INTEGER 0 */
	static const uint8_t nvctr[] = { 0x02, 0x01, 0x00 };
	uint8_t serial[8] = { };
	mbedtls_x509write_cert crt;
	mbedtls_pk_context pk;
	uint8_t *der = NULL;
	TEE_Result res = TEE_ERROR_GENERIC;
	size_t i = 0;
	int len = 0;

	der = TEE_Malloc(DBL_CERT_MAX, TEE_MALLOC_FILL_ZERO);
	if (!der)
		return TEE_ERROR_OUT_OF_MEMORY;
	mbedtls_x509write_crt_init(&crt);
	mbedtls_pk_init(&pk);

	if (mbedtls_pk_setup(&pk,
			     mbedtls_pk_info_from_type(MBEDTLS_PK_ECKEY))) {
		res = TEE_ERROR_GENERIC;
		goto out;
	}
	res = load_slot(slot, mbedtls_pk_ec(pk));
	if (res)
		goto out;

	/* Random positive serial, like cert_create */
	TEE_GenerateRandom(serial, sizeof(serial));
	serial[0] &= 0x7f;
	serial[0] |= 0x01;

	res = TEE_ERROR_GENERIC;
	mbedtls_x509write_crt_set_version(&crt, MBEDTLS_X509_CRT_VERSION_3);
	mbedtls_x509write_crt_set_md_alg(&crt, MBEDTLS_MD_SHA256);
	mbedtls_x509write_crt_set_subject_key(&crt, &pk);
	mbedtls_x509write_crt_set_issuer_key(&crt, &pk);
	if (mbedtls_x509write_crt_set_serial_raw(&crt, serial,
						 sizeof(serial)) ||
	    mbedtls_x509write_crt_set_subject_name(&crt, cn) ||
	    mbedtls_x509write_crt_set_issuer_name(&crt, cn) ||
	    mbedtls_x509write_crt_set_validity(&crt, CERT_NOT_BEFORE,
					       CERT_NOT_AFTER) ||
	    mbedtls_x509write_crt_set_subject_key_identifier(&crt) ||
	    mbedtls_x509write_crt_set_authority_key_identifier(&crt) ||
	    mbedtls_x509write_crt_set_basic_constraints(&crt, 0, -1) ||
	    mbedtls_x509write_crt_set_extension(&crt, OID_TFW_NVCOUNTER,
		MBEDTLS_OID_SIZE(OID_TFW_NVCOUNTER), 1, nvctr, sizeof(nvctr)))
		goto out;
	for (i = 0; i < n_ext; i++)
		if (mbedtls_x509write_crt_set_extension(&crt, exts[i].oid,
				exts[i].oid_len, 1, exts[i].val,
				exts[i].val_len))
			goto out;

	/* Writes at the end of the buffer, returns the length */
	len = mbedtls_x509write_crt_der(&crt, der, DBL_CERT_MAX, dbl_key_rng,
					NULL);
	if (len <= 0)
		goto out;
	if (out->memref.size < (size_t)len) {
		out->memref.size = len;
		res = TEE_ERROR_SHORT_BUFFER;
		goto out;
	}
	memcpy(out->memref.buffer, der + DBL_CERT_MAX - len, len);
	out->memref.size = len;
	res = TEE_SUCCESS;
out:
	mbedtls_x509write_crt_free(&crt);
	mbedtls_pk_free(&pk);
	TEE_Free(der);
	return res;
}

static TEE_Result sign_tkc(uint32_t pt, TEE_Param params[TEE_NUM_PARAMS])
{
	uint8_t tw[SPKI_P256_LEN] = { };
	uint8_t ntw[SPKI_P256_LEN] = { };
	uint32_t slot = 0;
	TEE_Result res = TEE_ERROR_GENERIC;
	const struct tbb_ext exts[] = {
		{ OID_TRUSTED_WORLD_PK, MBEDTLS_OID_SIZE(OID_TRUSTED_WORLD_PK),
		  tw, sizeof(tw) },
		{ OID_NON_TRUSTED_WORLD_PK,
		  MBEDTLS_OID_SIZE(OID_NON_TRUSTED_WORLD_PK), ntw, sizeof(ntw) },
	};

	if (pt != TEE_PARAM_TYPES(TEE_PARAM_TYPE_VALUE_INPUT,
				  TEE_PARAM_TYPE_MEMREF_INPUT,
				  TEE_PARAM_TYPE_MEMREF_INPUT,
				  TEE_PARAM_TYPE_MEMREF_OUTPUT))
		return TEE_ERROR_BAD_PARAMETERS;
	slot = params[0].value.a;
	if (slot >= DBL_UNITKEY_SLOTS)
		return TEE_ERROR_BAD_PARAMETERS;
	res = world_spki(params[1].memref.buffer, params[1].memref.size, tw);
	if (!res)
		res = world_spki(params[2].memref.buffer,
				 params[2].memref.size, ntw);
	if (res)
		return res;

	return root_cert(slot, TKC_CN, exts, ARRAY_SIZE(exts), &params[3]);
}

/* DigestInfo DER: SEQUENCE { AlgorithmIdentifier sha256, OCTET STRING hash } */
static void digest_info(uint8_t out[DIGEST_INFO_LEN], const uint8_t hash[32])
{
	static const uint8_t prefix[] = {
		0x30, 0x31, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01,
		0x65, 0x03, 0x04, 0x02, 0x01, 0x05, 0x00, 0x04, 0x20,
	};

	memcpy(out, prefix, sizeof(prefix));
	memcpy(out + sizeof(prefix), hash, 32);
}

static TEE_Result sign_cfg(uint32_t pt, TEE_Param params[TEE_NUM_PARAMS])
{
	/* hw_config isn't used (TF-A patch): cert_create writes a zero hash */
	static const uint8_t zero[32] = { };
	uint8_t hw[DIGEST_INFO_LEN] = { };
	uint8_t fw[DIGEST_INFO_LEN] = { };
	uint32_t slot = 0;
	const struct tbb_ext exts[] = {
		{ OID_HW_CONFIG_HASH, MBEDTLS_OID_SIZE(OID_HW_CONFIG_HASH),
		  hw, sizeof(hw) },
		{ OID_FW_CONFIG_HASH, MBEDTLS_OID_SIZE(OID_FW_CONFIG_HASH),
		  fw, sizeof(fw) },
	};

	if (pt != TEE_PARAM_TYPES(TEE_PARAM_TYPE_VALUE_INPUT,
				  TEE_PARAM_TYPE_MEMREF_INPUT,
				  TEE_PARAM_TYPE_MEMREF_OUTPUT,
				  TEE_PARAM_TYPE_NONE))
		return TEE_ERROR_BAD_PARAMETERS;
	slot = params[0].value.a;
	if (slot >= DBL_UNITKEY_SLOTS || params[1].memref.size != 32)
		return TEE_ERROR_BAD_PARAMETERS;
	digest_info(hw, zero);
	/* Copy first: the client can change shared memory at any time */
	digest_info(fw, params[1].memref.buffer);

	return root_cert(slot, CFG_CN, exts, ARRAY_SIZE(exts), &params[2]);
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
	case DBL_UNITKEY_CMD_GET_PUBKEYS:
		return get_pubkeys(param_types, params);
	case DBL_UNITKEY_CMD_SIGN_FSBL:
		return sign_fsbl(param_types, params);
	case DBL_UNITKEY_CMD_SIGN_TKC:
		return sign_tkc(param_types, params);
	case DBL_UNITKEY_CMD_SIGN_CFG:
		return sign_cfg(param_types, params);
	default:
		return TEE_ERROR_NOT_SUPPORTED;
	}
}

// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright 2026 Deadband Inc.
/*
 * dbl-tee: client for the DBL early TAs
 *
 *   dbl-tee mode               "stock" or "consent" (build mode of OP-TEE)
 *   dbl-tee deviceid-pubkey    DeviceID public key, hex SEC1 uncompressed
 *   dbl-tee attest NONCE_HEX   hex r||s over SHA-256(prefix || nonce)
 *
 * Consent session unitkey TA:
 *   dbl-tee unitkey-pubkeys    slot public keys, one hex X||Y per line
 *   dbl-tee sign-fsbl PK_IDX IMAGE_VERSION IN OUT
 *                              STM32 image signed with slot PK_IDX
 *   dbl-tee sign-tkc SLOT TW_HEX NTW_HEX OUT
 *                              TF-A trusted key certificate (DER) for the
 *                              world public keys (hex SEC1 uncompressed)
 *   dbl-tee sign-cfg SLOT FWCFG_SHA256_HEX OUT
 *                              TF-A STM32MP config certificate (DER) for
 *                              the fw_config hash (sha256sum fw-config.bin)
 *
 * OP-TEE without the consent TA reports stock
 */
#include <dbl_tee.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <tee_client_api.h>
#include <unistd.h>

static TEEC_Context ctx;
static TEEC_Session sess;

static TEEC_Result open_ta(const TEEC_UUID *uuid)
{
	uint32_t origin = 0;
	TEEC_Result res = TEEC_InitializeContext(NULL, &ctx);

	if (res != TEEC_SUCCESS)
		return res;
	res = TEEC_OpenSession(&ctx, &sess, uuid, TEEC_LOGIN_PUBLIC, NULL,
			       NULL, &origin);
	if (res != TEEC_SUCCESS)
		TEEC_FinalizeContext(&ctx);
	return res;
}

static void close_ta(void)
{
	TEEC_CloseSession(&sess);
	TEEC_FinalizeContext(&ctx);
}

static void print_hex(const uint8_t *buf, size_t len)
{
	for (size_t i = 0; i < len; i++)
		printf("%02x", buf[i]);
	printf("\n");
}

static int nibble(char c)
{
	if (c >= '0' && c <= '9')
		return c - '0';
	if (c >= 'a' && c <= 'f')
		return c - 'a' + 10;
	if (c >= 'A' && c <= 'F')
		return c - 'A' + 10;
	return -1;
}

static int parse_hex(const char *s, uint8_t *out, size_t max, size_t *len)
{
	size_t n = strlen(s);

	if (!n || n % 2 || n / 2 > max)
		return -1;
	for (size_t i = 0; i < n / 2; i++) {
		int hi = nibble(s[2 * i]);
		int lo = nibble(s[2 * i + 1]);

		if (hi < 0 || lo < 0)
			return -1;
		out[i] = hi << 4 | lo;
	}
	*len = n / 2;
	return 0;
}

static int fail(const char *what, TEEC_Result res)
{
	fprintf(stderr, "dbl-tee: %s: 0x%08x\n", what, res);
	return 1;
}

/* TA reported output size, refused if larger than the buffer */
static int out_size(const TEEC_TempMemoryReference *ref, size_t max,
		    size_t *len)
{
	if (ref->size > max) {
		fprintf(stderr, "dbl-tee: TA output %zu > %zu bytes\n",
			ref->size, max);
		return -1;
	}
	*len = ref->size;
	return 0;
}

static int cmd_mode(void)
{
	const TEEC_UUID uuid = DBL_CONSENT_UUID;
	TEEC_Operation op = { };
	uint32_t origin = 0;
	TEEC_Result res = open_ta(&uuid);

	if (res == TEEC_ERROR_ITEM_NOT_FOUND) {
		fprintf(stderr, "dbl-tee: no consent TA\n");
		printf("stock\n");
		return 0;
	}
	if (res != TEEC_SUCCESS)
		return fail("open consent TA", res);

	op.paramTypes = TEEC_PARAM_TYPES(TEEC_VALUE_OUTPUT, TEEC_NONE,
					 TEEC_NONE, TEEC_NONE);
	res = TEEC_InvokeCommand(&sess, DBL_CONSENT_CMD_GET_MODE, &op, &origin);
	close_ta();
	if (res != TEEC_SUCCESS)
		return fail("get mode", res);
	printf("%s\n", op.params[0].value.a == DBL_MODE_CONSENT ?
	       "consent" : "stock");
	return 0;
}

static int cmd_pubkey(void)
{
	const TEEC_UUID uuid = DBL_DEVICEID_UUID;
	uint8_t pub[DBL_DEVICEID_PUBKEY_SIZE] = { };
	size_t len = 0;
	TEEC_Operation op = { };
	uint32_t origin = 0;
	TEEC_Result res = open_ta(&uuid);

	if (res != TEEC_SUCCESS)
		return fail("open deviceid TA", res);
	op.paramTypes = TEEC_PARAM_TYPES(TEEC_MEMREF_TEMP_OUTPUT, TEEC_NONE,
					 TEEC_NONE, TEEC_NONE);
	op.params[0].tmpref.buffer = pub;
	op.params[0].tmpref.size = sizeof(pub);
	res = TEEC_InvokeCommand(&sess, DBL_DEVICEID_CMD_GET_PUBKEY, &op,
				 &origin);
	close_ta();
	if (res != TEEC_SUCCESS)
		return fail("get pubkey", res);
	if (out_size(&op.params[0].tmpref, sizeof(pub), &len))
		return 1;
	print_hex(pub, len);
	return 0;
}

static int cmd_attest(const char *nonce_hex)
{
	const TEEC_UUID uuid = DBL_DEVICEID_UUID;
	uint8_t nonce[DBL_ATTEST_NONCE_MAX] = { };
	uint8_t sig[DBL_DEVICEID_SIG_SIZE] = { };
	size_t nonce_len = 0;
	size_t sig_len = 0;
	TEEC_Operation op = { };
	uint32_t origin = 0;
	TEEC_Result res = TEEC_ERROR_GENERIC;

	if (parse_hex(nonce_hex, nonce, sizeof(nonce), &nonce_len)) {
		fprintf(stderr, "dbl-tee: nonce: 1-%d bytes as hex\n",
			DBL_ATTEST_NONCE_MAX);
		return 2;
	}
	res = open_ta(&uuid);
	if (res != TEEC_SUCCESS)
		return fail("open deviceid TA", res);
	op.paramTypes = TEEC_PARAM_TYPES(TEEC_MEMREF_TEMP_INPUT,
					 TEEC_MEMREF_TEMP_OUTPUT,
					 TEEC_NONE, TEEC_NONE);
	op.params[0].tmpref.buffer = nonce;
	op.params[0].tmpref.size = nonce_len;
	op.params[1].tmpref.buffer = sig;
	op.params[1].tmpref.size = sizeof(sig);
	res = TEEC_InvokeCommand(&sess, DBL_DEVICEID_CMD_ATTEST, &op, &origin);
	close_ta();
	if (res != TEEC_SUCCESS)
		return fail("attest", res);
	if (out_size(&op.params[1].tmpref, sizeof(sig), &sig_len))
		return 1;
	print_hex(sig, sig_len);
	return 0;
}

static int parse_u32(const char *s, uint32_t *v)
{
	char *end = NULL;
	unsigned long long n = 0;

	if (*s < '0' || *s > '9')
		return -1;
	errno = 0;
	n = strtoull(s, &end, 0);
	if (errno || *end || n > UINT32_MAX)
		return -1;
	*v = n;
	return 0;
}

/* Removes a partial output file on error */
static int write_file(const char *path, const void *buf, size_t len)
{
	FILE *f = fopen(path, "wb");
	int err = 0;

	if (!f) {
		perror(path);
		return 1;
	}
	if (fwrite(buf, 1, len, f) != len)
		err = 1;
	if (fclose(f))
		err = 1;
	if (err) {
		perror(path);
		unlink(path);
	}
	return err;
}

static int cmd_unitkey_pubkeys(void)
{
	const TEEC_UUID uuid = DBL_UNITKEY_UUID;
	uint8_t xy[DBL_UNITKEY_SLOTS * 64] = { };
	TEEC_Operation op = { };
	uint32_t origin = 0;
	TEEC_Result res = open_ta(&uuid);

	if (res != TEEC_SUCCESS)
		return fail("open unitkey TA", res);
	op.paramTypes = TEEC_PARAM_TYPES(TEEC_MEMREF_TEMP_OUTPUT, TEEC_NONE,
					 TEEC_NONE, TEEC_NONE);
	op.params[0].tmpref.buffer = xy;
	op.params[0].tmpref.size = sizeof(xy);
	res = TEEC_InvokeCommand(&sess, DBL_UNITKEY_CMD_GET_PUBKEYS, &op,
				 &origin);
	close_ta();
	if (res != TEEC_SUCCESS)
		return fail("get pubkeys", res);
	if (op.params[0].tmpref.size != sizeof(xy)) {
		fprintf(stderr, "dbl-tee: TA returned %zu bytes, expected %zu\n",
			op.params[0].tmpref.size, sizeof(xy));
		return 1;
	}
	for (int i = 0; i < DBL_UNITKEY_SLOTS; i++)
		print_hex(xy + 64 * i, 64);
	return 0;
}

static int cmd_sign_fsbl(const char *idx_s, const char *ver_s,
			 const char *in_path, const char *out_path)
{
	const TEEC_UUID uuid = DBL_UNITKEY_UUID;
	size_t out_max = DBL_FSBL_MAX + 32;
	uint8_t *in = malloc(DBL_FSBL_MAX + 1);
	uint8_t *out = malloc(out_max);
	TEEC_Operation op = { };
	uint32_t origin = 0;
	uint32_t idx = 0;
	uint32_t ver = 0;
	size_t in_len = 0;
	size_t out_len = 0;
	TEEC_Result res = TEEC_ERROR_GENERIC;
	FILE *f = NULL;
	int ret = 1;

	if (!in || !out) {
		fprintf(stderr, "dbl-tee: out of memory\n");
		goto out;
	}
	if (parse_u32(idx_s, &idx) || idx >= DBL_UNITKEY_SLOTS ||
	    parse_u32(ver_s, &ver)) {
		fprintf(stderr, "dbl-tee: PK_IDX 0-%d, IMAGE_VERSION u32\n",
			DBL_UNITKEY_SLOTS - 1);
		ret = 2;
		goto out;
	}
	f = fopen(in_path, "rb");
	if (!f) {
		perror(in_path);
		goto out;
	}
	in_len = fread(in, 1, DBL_FSBL_MAX + 1, f);
	if (ferror(f)) {
		perror(in_path);
		fclose(f);
		goto out;
	}
	fclose(f);
	if (in_len > DBL_FSBL_MAX) {
		fprintf(stderr, "dbl-tee: %s larger than %d bytes\n", in_path,
			DBL_FSBL_MAX);
		goto out;
	}

	res = open_ta(&uuid);
	if (res != TEEC_SUCCESS) {
		ret = fail("open unitkey TA", res);
		goto out;
	}
	op.paramTypes = TEEC_PARAM_TYPES(TEEC_VALUE_INPUT,
					 TEEC_MEMREF_TEMP_INPUT,
					 TEEC_MEMREF_TEMP_OUTPUT, TEEC_NONE);
	op.params[0].value.a = idx;
	op.params[0].value.b = ver;
	op.params[1].tmpref.buffer = in;
	op.params[1].tmpref.size = in_len;
	op.params[2].tmpref.buffer = out;
	op.params[2].tmpref.size = out_max;
	res = TEEC_InvokeCommand(&sess, DBL_UNITKEY_CMD_SIGN_FSBL, &op,
				 &origin);
	close_ta();
	if (res != TEEC_SUCCESS)
		ret = fail("sign fsbl", res);
	else if (!out_size(&op.params[2].tmpref, out_max, &out_len))
		ret = write_file(out_path, out, out_len);
out:
	free(in);
	free(out);
	return ret;
}

static int cmd_sign_tkc(const char *slot_s, const char *tw_hex,
			const char *ntw_hex, const char *out_path)
{
	const TEEC_UUID uuid = DBL_UNITKEY_UUID;
	uint8_t tw[65] = { };
	uint8_t ntw[65] = { };
	uint8_t der[DBL_CERT_MAX] = { };
	size_t der_len = 0;
	size_t tw_len = 0;
	size_t ntw_len = 0;
	TEEC_Operation op = { };
	uint32_t origin = 0;
	uint32_t slot = 0;
	TEEC_Result res = TEEC_ERROR_GENERIC;

	if (parse_u32(slot_s, &slot) || slot >= DBL_UNITKEY_SLOTS ||
	    parse_hex(tw_hex, tw, sizeof(tw), &tw_len) ||
	    tw_len != sizeof(tw) ||
	    parse_hex(ntw_hex, ntw, sizeof(ntw), &ntw_len) ||
	    ntw_len != sizeof(ntw)) {
		fprintf(stderr, "dbl-tee: SLOT 0-%d, keys 65 bytes hex (04 || X || Y)\n",
			DBL_UNITKEY_SLOTS - 1);
		return 2;
	}

	res = open_ta(&uuid);
	if (res != TEEC_SUCCESS)
		return fail("open unitkey TA", res);
	op.paramTypes = TEEC_PARAM_TYPES(TEEC_VALUE_INPUT,
					 TEEC_MEMREF_TEMP_INPUT,
					 TEEC_MEMREF_TEMP_INPUT,
					 TEEC_MEMREF_TEMP_OUTPUT);
	op.params[0].value.a = slot;
	op.params[1].tmpref.buffer = tw;
	op.params[1].tmpref.size = sizeof(tw);
	op.params[2].tmpref.buffer = ntw;
	op.params[2].tmpref.size = sizeof(ntw);
	op.params[3].tmpref.buffer = der;
	op.params[3].tmpref.size = sizeof(der);
	res = TEEC_InvokeCommand(&sess, DBL_UNITKEY_CMD_SIGN_TKC, &op, &origin);
	close_ta();
	if (res != TEEC_SUCCESS)
		return fail("sign tkc", res);
	if (out_size(&op.params[3].tmpref, sizeof(der), &der_len))
		return 1;
	return write_file(out_path, der, der_len);
}

static int cmd_sign_cfg(const char *slot_s, const char *hash_hex,
			const char *out_path)
{
	const TEEC_UUID uuid = DBL_UNITKEY_UUID;
	uint8_t hash[32] = { };
	uint8_t der[DBL_CERT_MAX] = { };
	size_t der_len = 0;
	size_t hash_len = 0;
	TEEC_Operation op = { };
	uint32_t origin = 0;
	uint32_t slot = 0;
	TEEC_Result res = TEEC_ERROR_GENERIC;

	if (parse_u32(slot_s, &slot) || slot >= DBL_UNITKEY_SLOTS ||
	    parse_hex(hash_hex, hash, sizeof(hash), &hash_len) ||
	    hash_len != sizeof(hash)) {
		fprintf(stderr, "dbl-tee: SLOT 0-%d, hash 32 bytes hex\n",
			DBL_UNITKEY_SLOTS - 1);
		return 2;
	}

	res = open_ta(&uuid);
	if (res != TEEC_SUCCESS)
		return fail("open unitkey TA", res);
	op.paramTypes = TEEC_PARAM_TYPES(TEEC_VALUE_INPUT,
					 TEEC_MEMREF_TEMP_INPUT,
					 TEEC_MEMREF_TEMP_OUTPUT, TEEC_NONE);
	op.params[0].value.a = slot;
	op.params[1].tmpref.buffer = hash;
	op.params[1].tmpref.size = sizeof(hash);
	op.params[2].tmpref.buffer = der;
	op.params[2].tmpref.size = sizeof(der);
	res = TEEC_InvokeCommand(&sess, DBL_UNITKEY_CMD_SIGN_CFG, &op, &origin);
	close_ta();
	if (res != TEEC_SUCCESS)
		return fail("sign cfg", res);
	if (out_size(&op.params[2].tmpref, sizeof(der), &der_len))
		return 1;
	return write_file(out_path, der, der_len);
}

int main(int argc, char *argv[])
{
	if (argc == 2 && !strcmp(argv[1], "mode"))
		return cmd_mode();
	if (argc == 2 && !strcmp(argv[1], "deviceid-pubkey"))
		return cmd_pubkey();
	if (argc == 3 && !strcmp(argv[1], "attest"))
		return cmd_attest(argv[2]);
	if (argc == 2 && !strcmp(argv[1], "unitkey-pubkeys"))
		return cmd_unitkey_pubkeys();
	if (argc == 6 && !strcmp(argv[1], "sign-fsbl"))
		return cmd_sign_fsbl(argv[2], argv[3], argv[4], argv[5]);
	if (argc == 6 && !strcmp(argv[1], "sign-tkc"))
		return cmd_sign_tkc(argv[2], argv[3], argv[4], argv[5]);
	if (argc == 5 && !strcmp(argv[1], "sign-cfg"))
		return cmd_sign_cfg(argv[2], argv[3], argv[4]);

	fprintf(stderr,
		"usage: dbl-tee mode\n"
		"       dbl-tee deviceid-pubkey\n"
		"       dbl-tee attest NONCE_HEX\n"
		"       dbl-tee unitkey-pubkeys\n"
		"       dbl-tee sign-fsbl PK_IDX IMAGE_VERSION IN OUT\n"
		"       dbl-tee sign-tkc SLOT TW_HEX NTW_HEX OUT\n"
		"       dbl-tee sign-cfg SLOT FWCFG_SHA256_HEX OUT\n");
	return 2;
}

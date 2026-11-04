// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright 2026 Deadband Inc.
/*
 * dbl-tee: client for the DBL early TAs
 *
 *   dbl-tee mode               "stock" or "consent" (build mode of OP-TEE)
 *   dbl-tee deviceid-pubkey    DeviceID public key, hex SEC1 uncompressed
 *   dbl-tee attest NONCE_HEX   hex r||s over SHA-256(prefix || nonce)
 *
 * OP-TEE without the consent TA reports stock
 */
#include <dbl_tee.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <tee_client_api.h>

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

static int parse_hex(const char *s, uint8_t *out, size_t max, size_t *len)
{
	size_t n = strlen(s);

	if (!n || n % 2 || n / 2 > max)
		return -1;
	for (size_t i = 0; i < n / 2; i++) {
		unsigned int b = 0;

		if (sscanf(s + 2 * i, "%2x", &b) != 1)
			return -1;
		out[i] = b;
	}
	*len = n / 2;
	return 0;
}

static int fail(const char *what, TEEC_Result res)
{
	fprintf(stderr, "dbl-tee: %s: 0x%08x\n", what, res);
	return 1;
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
	print_hex(pub, op.params[0].tmpref.size);
	return 0;
}

static int cmd_attest(const char *nonce_hex)
{
	const TEEC_UUID uuid = DBL_DEVICEID_UUID;
	uint8_t nonce[DBL_ATTEST_NONCE_MAX] = { };
	uint8_t sig[DBL_DEVICEID_SIG_SIZE] = { };
	size_t nonce_len = 0;
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
	print_hex(sig, op.params[1].tmpref.size);
	return 0;
}

int main(int argc, char *argv[])
{
	if (argc == 2 && !strcmp(argv[1], "mode"))
		return cmd_mode();
	if (argc == 2 && !strcmp(argv[1], "deviceid-pubkey"))
		return cmd_pubkey();
	if (argc == 3 && !strcmp(argv[1], "attest"))
		return cmd_attest(argv[2]);

	fprintf(stderr,
		"usage: dbl-tee mode\n"
		"       dbl-tee deviceid-pubkey\n"
		"       dbl-tee attest NONCE_HEX\n");
	return 2;
}

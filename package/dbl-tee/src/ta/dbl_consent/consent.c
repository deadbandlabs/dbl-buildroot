// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright 2026 Deadband Inc.
/*
 * Reports if current OP-TEE is a consent build.
 */
#include <dbl_tee.h>
#include <tee_internal_api.h>

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
	if (cmd != DBL_CONSENT_CMD_GET_MODE)
		return TEE_ERROR_NOT_SUPPORTED;
	if (param_types != TEE_PARAM_TYPES(TEE_PARAM_TYPE_VALUE_OUTPUT,
					   TEE_PARAM_TYPE_NONE,
					   TEE_PARAM_TYPE_NONE,
					   TEE_PARAM_TYPE_NONE))
		return TEE_ERROR_BAD_PARAMETERS;

#ifdef DBL_CONSENT
	params[0].value.a = DBL_MODE_CONSENT;
#else
	params[0].value.a = DBL_MODE_STOCK;
#endif
	params[0].value.b = 0;
	return TEE_SUCCESS;
}

/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Copyright 2026 Deadband Inc. */
#ifndef USER_TA_HEADER_DEFINES_H
#define USER_TA_HEADER_DEFINES_H

#include <dbl_tee.h>

#define TA_UUID			DBL_UNITKEY_UUID
#define TA_FLAGS		(TA_FLAG_SINGLE_INSTANCE | TA_FLAG_MULTI_SESSION)
#define TA_STACK_SIZE		(16 * 1024)
/* Two FSBL copies (input + output buffer) */
#define TA_DATA_SIZE		(640 * 1024)
#define TA_DESCRIPTION		"DBL unit keys"

#endif /* USER_TA_HEADER_DEFINES_H */

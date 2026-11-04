/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Copyright 2026 Deadband Inc. */
#ifndef USER_TA_HEADER_DEFINES_H
#define USER_TA_HEADER_DEFINES_H

#include <dbl_tee.h>

#define TA_UUID			DBL_DEVICEID_UUID
#define TA_FLAGS		(TA_FLAG_SINGLE_INSTANCE | TA_FLAG_MULTI_SESSION)
#define TA_STACK_SIZE		(8 * 1024)
#define TA_DATA_SIZE		(32 * 1024)
#define TA_DESCRIPTION		"DBL DeviceID attestation"

#endif /* USER_TA_HEADER_DEFINES_H */

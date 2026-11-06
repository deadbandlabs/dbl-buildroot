#!/usr/bin/env sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright 2026 Deadband Inc.
#
# dbl-bootid-example.bin must match dbl-bootid.toml with correct layout
set -eu

cd "$(git rev-parse --show-toplevel)"
python3 support/dbl-bootid.py check board/myd-yf135/dbl-bootid.toml board/myd-yf135/dbl-bootid-example.bin

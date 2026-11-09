#!/usr/bin/env sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright 2026 Deadband Inc.
#
# Checl each dbl-bootid-example.bin slot holds an object of its
# dbl-bootid.toml format (signatures unchecked)
set -eu

cd "$(git rev-parse --show-toplevel)"
python3 board/myd-yf135/dbl-bootid.py check board/myd-yf135/dbl-bootid.toml board/myd-yf135/dbl-bootid-example.bin

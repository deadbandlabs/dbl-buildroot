# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright 2026 Deadband Inc.
#
# sha256 for sources pinned past the Buildroot release, keyed by download filename
# Used by `make nix-lock` only (buildroot.nix extraSha256Hashes)
# Plain `make` skips hash checks for custom versions
{
  # Kernel + toolchain headers
  # https://cdn.kernel.org/pub/linux/kernel/v6.x/sha256sums.asc
  "linux-6.12.112.tar.xz" = "164dc9d1f6c93c61a15e1f071c48379b467f2b17c469cce7223471968208ed03";

  # U-Boot (as buildroot 2026.08 uboot.hash)
  "u-boot-2026.07.tar.bz2" = "78e8bfc382fe388f9b55aa1daf8c563522a037779b5d4c349d1415e381f1243e";

  # TF-A, GitHub archive of lts-v2.14.10 (c50e04eba2ca)
  "arm-trusted-firmware-lts-v2.14.10.tar.gz" =
    "27ea020f37b253f2638fdeb1f16ce7f59bfecf955777fee2feeebe423bd7a929";

  # mbedTLS for TF-A TBB (package/dbl-tf-a-mbedtls/dbl-tf-a-mbedtls.hash)
  "mbedtls-3.6.7.tar.bz2" = "a7e8bcbec0e6f761b4af24f25677626b35f762f68eef79c08677a363212d11f6";
}

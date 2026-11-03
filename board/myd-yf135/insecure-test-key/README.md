# INSECURE test key: public, do not trust

The private key in this directory is public. Anyone can sign with it. A
device that trusts it accepts images from anyone.

This key is used for reproducible builds and signed-image tests in this
repository and in CI. Each build signs the rootfs FIT with this key. Each
build uses this certificate as the default RAUC keyring. A parent config
can set its own keys.

- `insecure-test-key.key`: RSA-3072 private key
- `insecure-test-key.crt`: self-signed certificate,
  `CN=dbl-INSECURE-test-key-DO-NOT-TRUST`

U-Boot names the verifying key at boot. A test-signed image shows
`sha256,rsa3072:insecure-test-key+` in the boot log.

## Products

Ship your own keys. Set in your parent fragment:

- `BR2_PACKAGE_DBL_FIT_PUBKEYS`: your FIT certificates. List two
  (primary and backup) to accept either. U-Boot uses
  `required-mode = "any"`. Images built here are test-signed. Re-sign
  them with `sign-rootimg.sh` before release. The script supports
  PKCS#11. Unsigned or test-signed images then fail to boot.
- `BR2_PACKAGE_DBL_RAUC_KEYRING`: your RAUC keyring. List one or more
  certificates.
- `BR2_PACKAGE_DBL_VERITY_SIG_CERTS`: certificates for signed sysext
  images.

Do not list this certificate in a product build.

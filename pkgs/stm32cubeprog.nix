# STM32CubeProgrammer CLI tools
# Supporting CLI-only, GUI launcher removed/nonfunctional
#
# The .linux installer in the zip depends on a bundled Java 8, which is
# difficult to obtain. Instead we run the .exe (an install4j archive) with
# Nix's own modern JDK, which works cleanly.
#
# Note: ST's license prohibits automatic download; add the zip to the Nix store
# manually before building:
#
#   nix-store --add-fixed sha256 /path/to/SetupSTM32CubeProgrammer_linux_64.zip
#   direnv reload  (or re-enter the dev shell)
#
# Provides: STM32_Programmer_CLI  STM32_SigningTool_CLI  STM32_KeyGen_CLI
#
# USB access without sudo requires the bundled udev rules.
#
# Arch (or most systemd/udev distros):
#   sudo cp $(nix eval --raw .#stm32cubeprog)/lib/udev/rules.d/*.rules /etc/udev/rules.d/
#   sudo udevadm control --reload-rules && sudo udevadm trigger
#   (replug the board after)
#
# NixOS:
#   services.udev.packages = [ inputs.dbl.packages.x86_64-linux.stm32cubeprog ];
#
# One-off without rules: sudo $(which STM32_Programmer_CLI) -l usb
#
# Inspired by Nixpkgs PR #475250 (github.com/mksafavi/nixpkgs @ efbddd7),
# simplified for CLI use and updated for v2.22.0
{
  lib,
  stdenv,
  requireFile,
  autoPatchelfHook,
  unzip,
  openjdk,
  buildFHSEnv,
  libusb1,
  glib,
  libz,
  libkrb5,
  openssl,
  pcsclite,
}:

let
  pname = "stm32cubeprog";
  version = "2.22.0";
in
stdenv.mkDerivation {
  inherit version pname;

  src = requireFile {
    name = "SetupSTM32CubeProgrammer_linux_64.zip";
    url = "https://www.st.com/en/development-tools/stm32cubeprog.html";
    sha256 = "fffa017abb4da14582e129aa9a1e4f87e6d0719a3cb950c0184f4cb48ab60aa7";
  };

  nativeBuildInputs = [
    openjdk
    unzip
    autoPatchelfHook
  ];

  # Note: Ignores all unsatisfied deps. ST's installer ships Qt platform plugins and
  # STLink/HSM libs we neither provide nor need for CLI use. The CLI binaries
  # themselves only require libusb and openssl at runtime, which are in buildInputs.
  autoPatchelfIgnoreMissingDeps = true;

  buildInputs = [
    libusb1
    glib
    libz
    libkrb5
    openssl
    pcsclite
  ];

  # Extract the .exe (install4j archive) and plant a fake JRE stub so the
  # installer doesn't try to use its bundled Java 8.
  unpackCmd = ''
    unzip -d stm32cubeprg $curSrc SetupSTM32CubeProgrammer-${version}.exe
    mkdir -p stm32cubeprg/jre/bin
    touch stm32cubeprg/jre/bin/java
  '';

  installPhase =
    let
      # Minimal FHS env so the install4j .exe can find Java at runtime.
      installEnv = buildFHSEnv {
        name = "installer-env";
        targetPkgs = pkgs: [ openjdk ];
        runScript = "java";
      };
    in
    ''
      runHook preInstall

      ${installEnv}/bin/${installEnv.name} \
        -jar -DINSTALL_PATH=$out \
        SetupSTM32CubeProgrammer-${version}.exe \
        -options-system
      rm -rf $out/jre

      # udev rules for USB access without sudo
      mkdir -p $out/lib/udev/rules.d/
      mv $out/Drivers/rules/* $out/lib/udev/rules.d/


      runHook postInstall
    '';


  meta = {
    description = "STM32CubeProgrammer CLI for flashing STM32 devices via USB DFU, UART, SWD/JTAG";
    homepage = "https://www.st.com/en/development-tools/stm32cubeprog.html";
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" ];
    mainProgram = "STM32_Programmer_CLI";
  };
}

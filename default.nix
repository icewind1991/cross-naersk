{
  rust-bin,
  lib,
  pkgsCross,
  callPackage,
  hostPlatform,
  naersk,
  stdenv,
  fetchurl,
  perl,
  mkShell,
  freebsdCross,
  toolchain ? rust-bin.stable.latest.default
} @ inputs: let
  inherit (lib.strings) replaceStrings toUpper concatStrings hasInfix;
  inherit (builtins) removeAttrs foldl' map;

  freebsdSysrootX86 = callPackage ./freebsd-sysroot.nix {
    arch = "amd64";
    sha256 = "sha256-/XZXt0bPI9bTXrD+TR2KYzhE7wKpVAvKndWL3tqe5cg=";
    version = freebsdCross.versionData.revision;
  };

  recursiveMerge = callPackage ./merge.nix {};
  isMusl = hasInfix "-musl";

  buildCrossArgs = target: {
    targetDeps ? [],
    rustFlags ? (if isMusl target then "-C target-feature=+crt-static" else ""),
    cFlags ? "",
    targetStdenv,
    ...
  } @ args: let
    isHostTarget = targetStdenv.targetPlatform.config == stdenv.targetPlatform.config;
    # don't use the pkgsCross cc if the target is the host platform
    targetCc = if isHostTarget then stdenv.cc else targetStdenv.cc;
    targetUnderscore = replaceStrings ["-"] ["_"] target;
    targetUpperCase = toUpper targetUnderscore;
    rest = removeAttrs args ["rustFlags" "cc" "cFlags" "targetDeps"];
    # by adding the dependency in the (target specific) linker args instead of buildInputs
    # we can prevent it trying to link to it for host build dependencies
    rustFlagsWithDeps = rustFlags + concatStrings (map (targetDep: " -Clink-arg=-L${targetDep}/lib") targetDeps);
  in (recursiveMerge [
    {
      nativeBuildInputs = [targetCc stdenv.cc];
      "CARGO_TARGET_${targetUpperCase}_RUSTFLAGS" = rustFlagsWithDeps;
      "CARGO_TARGET_${targetUpperCase}_LINKER" = "${targetCc.targetPrefix}cc";
      "AR_${targetUnderscore}" = "${targetCc.targetPrefix}ar";
      "CC_${targetUnderscore}" = "${targetCc.targetPrefix}cc";
      "CCX_${targetUnderscore}" = "${targetCc.targetPrefix}ccx";
      "HOST_CC" = "${stdenv.cc.targetPrefix}cc";
      "CFLAGS_${targetUnderscore}" = cFlags;
    }
    rest
  ]);

  defaultCrossArgs = {
    "armv7-unknown-linux-musleabihf" = buildCrossArgs "armv7-unknown-linux-musleabihf" {
      targetStdenv = pkgsCross.muslpi.stdenv;
    };
    "armv7-unknown-linux-gnueabihf" = buildCrossArgs "armv7-unknown-linux-gnueabihf" {
      targetStdenv = pkgsCross.armv7l-hf-multiplatform.stdenv;
    };
    "aarch64-unknown-linux-gnu" = buildCrossArgs "aarch64-unknown-linux-gnu" {
      targetStdenv = pkgsCross.aarch64-multiplatform.stdenv;
    };
    "aarch64-unknown-linux-musl" = buildCrossArgs "aarch64-unknown-linux-musl" {
      targetStdenv = pkgsCross.aarch64-multiplatform-musl.stdenv;
      cFlags = "-mno-outline-atomics";
    };
    "i686-unknown-linux-musl" = buildCrossArgs "i686-unknown-linux-musl" {
      targetStdenv = pkgsCross.musl32.stdenv;
    };
    "i686-unknown-linux-gnu" = buildCrossArgs "i686-unknown-linux-gnu" {
      targetStdenv = pkgsCross.gnu32.stdenv;
    };
    "x86_64-pc-windows-gnu" = buildCrossArgs "x86_64-pc-windows-gnu" {
      targetStdenv = pkgsCross.mingwW64.stdenv;
      strictDeps = true;
      # rink wants perl for windows targets
      buildInputs = [perl];
      targetDeps = [pkgsCross.mingwW64.windows.pthreads];
      rustFlags = "-C target-feature=+crt-static";
    };
    "x86_64-unknown-freebsd" = buildCrossArgs "x86_64-unknown-freebsd" {
      targetStdenv = pkgsCross.x86_64-freebsd.stdenv;
      targetDeps = [freebsdSysrootX86];
      dontPatchELF = true;
      postInstall = ''
        patchelf --set-interpreter /libexec/ld-elf.so.1 $out/bin/*
      '';
      X86_64_UNKNOWN_FREEBSD_OPENSSL_DIR = freebsdSysrootX86;
      BINDGEN_EXTRA_CLANG_ARGS_x86_64_unknown_freebsd = "--sysroot=${freebsdSysrootX86}";
    };
    "x86_64-unknown-linux-musl" = buildCrossArgs "x86_64-unknown-linux-musl" {
      targetStdenv = pkgsCross.musl64.stdenv;
    };
    "x86_64-unknown-linux-gnu" = buildCrossArgs "x86_64-unknown-linux-gnu" {
      targetStdenv = pkgsCross.gnu64.stdenv;
    };
  };
  hostTarget = hostPlatform.config;
  naersk' = callPackage naersk {
    cargo = toolchain;
    rustc = toolchain;
  };
  crossArgs = options: recursiveMerge [defaultCrossArgs (options.crossArgs or {})];
in rec {
  buildPackage = target: let
    targetToolchain = toolchain.override {targets = [target];};
    naerskForTarget = callPackage naersk {
      cargo = targetToolchain;
      rustc = targetToolchain;
    };
    crossArgsForTarget = options:
      if hostTarget != target
      then (crossArgs options).${target} or {}
      else {};
    args = options:
      {
        CARGO_BUILD_TARGET = target;
      }
      // (builtins.removeAttrs options ["crossArgs"])
      // (crossArgsForTarget options);
  in
    options: naerskForTarget.buildPackage (args options);
  defaultCrossArgsForTargets = targets: recursiveMerge (map (target: defaultCrossArgs.${target} or {}) targets);
  execSufficForTarget = target: if lib.strings.hasInfix "windows" target then ".exe" else "";
  hostNaersk = naersk';
  mkShell = targets: args: let
    nonDeps = removeAttrs (defaultCrossArgsForTargets targets) ["nativeBuildInputs"];
    deps = (defaultCrossArgsForTargets targets).nativeBuildInputs;
  in
    inputs.mkShell (nonDeps
      // args
      // {
        nativeBuildInputs =
          deps
          ++ (args.nativeBuildInputs or [])
          ++ [
            (toolchain.override {targets = targets ++ [hostTarget];})
          ];
      });
}

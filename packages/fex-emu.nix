{ pkgs, lib, fetchFromGitHub, cmake, ninja, pkg-config, python3 }:

let
  # Based on: https://github.com/NixOS/nixpkgs/issues/24744#issuecomment-1927254475
  clangStdEnv = pkgs.stdenvAdapters.overrideCC pkgs.llvmPackages.stdenv (
    pkgs.llvmPackages.clang.override {
      bintools = pkgs.llvmPackages.bintools;
    }
  );
in
clangStdEnv.mkDerivation rec {
  pname = "fex-emu";
  version = "2412";
  src = fetchFromGitHub {
    repo = "FEX";
    owner = "FEX-Emu";
    rev = "FEX-${version}";
    hash = "sha256-l+I205EPpdbWrFhM7ZozmBVkMq6IjTjQkbKvSQrw554=";

    forceFetchGit = true;
    leaveDotGit = true;
    postFetch = ''
      cd $out
      ${pkgs.git}/bin/git reset
      ${pkgs.git}/bin/git submodule update --init --depth 1 \
        External/Vulkan-Headers \
        External/drm-headers \
        External/fmt \
        External/jemalloc \
        External/jemalloc_glibc \
        External/robin-map \
        External/vixl \
        External/xxhash \
        Source/Common/cpp-optparse
      find . -name .git -print0 | xargs -0 rm -rf
    '';
  };
  patches = [ ./fex-emu-shebang-absolute-path-fix.patch ];
  nativeBuildInputs = [
    cmake
    ninja
    pkg-config
    (python3.withPackages (ps: [ ps.setuptools ]))
  ];
  cmakeFlags = [
    (lib.cmakeFeature "OVERRIDE_VERSION" version)
    (lib.cmakeBool "BUILD_FEXCONFIG" false)
    (lib.cmakeBool "BUILD_TESTS" false)
  ];
}

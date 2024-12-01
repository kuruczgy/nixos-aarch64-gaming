{ pkgs, fetchFromGitHub }:

let
  clangStdEnv = pkgs.stdenvAdapters.overrideCC pkgs.llvmPackages.stdenv (
    pkgs.llvmPackages.clang.override {
      bintools = pkgs.llvmPackages.bintools;
    }
  );
in
clangStdEnv.mkDerivation {
  name = "fex-emu";
  src = fetchFromGitHub {
    repo = "FEX";
    owner = "FEX-Emu";
    rev = "22058c06a1f3585f66ed71765c9b6b652bdd66cc";
    hash = "sha256-Spn75tiYJmweZNbaYeR6u/omjMPyC2nBuz8SIQCZGGE=";
    # TODO: only selectively fetch some, as some contain prebuilt binaries
    fetchSubmodules = true;
  };
  patches = [ ./fex-emu-fixes.patch ];
  nativeBuildInputs = with pkgs; [
    git
    cmake
    ninja
    pkg-config
    nasm
    (python3.withPackages (ps: with ps; [
      clang
      setuptools
    ]))
  ];
  dontWrapQtApps = true;
  buildInputs = with pkgs; [
    openssl
    qt5.qtbase
    qt5.qtdeclarative
    qt5.qtquickcontrols
    qt5.qtquickcontrols2
  ];
}

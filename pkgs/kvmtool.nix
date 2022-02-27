{ stdenv, fetchgit, fetchurl, lib, zlib, libaio, libbfd }:
stdenv.mkDerivation {
  pname = "kvmtool";
  version = "2021-12-14";

  src = fetchgit {
    url = "https://git.kernel.org/pub/scm/linux/kernel/git/will/kvmtool.git";
    rev = "cdd7d8cc0109bb8e2a0a04c5fe904b5ad4f07a80";
    sha256 = "0gp0fq130q7m5z1gppan4cd5ip2zxr7hjx4z9aysjy0nj584rihk";
  };

  # x86: Fixed Unable to execute init process since glibc version 2.33
  patches = [ (fetchurl {
    url = "https://github.com/kvmtool/kvmtool/pull/5.patch";
    sha256 = "1ndp5xx01sghyhg58sym4q5na9af4la35nyh9lm8rh8ynk75q31s";
  }) ];

  buildInputs = [
    zlib libaio libbfd
  ];

  # libfd wants that
  NIX_CFLAGS_COMPILE = "-DPACKAGE=1 -DPACKAGE_VERSION=1";
  enableParallelBuilding = true;
  buildPhase = ''
    runHook preBuild
    # the SHELL passed to the make in our normal build phase is breaking feature detection
    make -j$NIX_BUILD_CORES
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    make install -j$NIX_BUILD_CORES prefix=${placeholder "out"}
    runHook postInstall
  '';

  meta = with lib; {
    description = "A lightweight tool for hosting KVM guests";
    homepage =
      "https://git.kernel.org/pub/scm/linux/kernel/git/will/kvmtool.git/tree/README";
    license = licenses.gpl2;
  };
}

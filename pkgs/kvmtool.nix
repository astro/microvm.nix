{ stdenv, fetchgit, lib, zlib, libaio, libbfd }:
stdenv.mkDerivation {
  pname = "kvmtool";
  version = "2021-08-31";

  src = fetchgit {
    url = "https://git.kernel.org/pub/scm/linux/kernel/git/will/kvmtool.git";
    rev = "2e7380db438defbc5aa24652fe10b7bf99822355";
    sha256 = "sha256-QhT0znxlLWhFtN2DiwU0Zl3IYJDpynX8DYBHVTxy8iU=";
  };

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

{ pkgs }:

with pkgs;

stdenv.mkDerivation {
  pname = "kvmtool";
  version = "2021-07-16";

  src = fetchgit {
    url = "git://git.kernel.org/pub/scm/linux/kernel/git/will/kvmtool.git";
    sha256 = "0gp7gp5zy0g074brph06azqyq862f3cnww3iscvpcl7q2b9jh38k";
  };

  buildInputs = [
    zlib libaio
    # FIXME: not detecting: libbfd
  ];
  buildPhase = "make -j$NIX_BUILD_CORES";

  installPhase = ''
    mkdir -p $out/bin
    cp -a lkvm $out/bin
  '';
}

{ stdenv, fetchgit }:

stdenv.mkDerivation {
  pname = "mktuntap";
  version = "1.0";

  src = fetchgit {
    url = "https://spectrum-os.org/git/mktuntap";
    sha256 = "sha256-r1m5jYPy2Z+B2cn12e7XnUxUXw6bOXeEHdU25fqR/W4=";
  };

  makeFlags = [ "prefix=${placeholder "out"}" ];
}

{ self, nixpkgs, system }:

with nixpkgs.legacyPackages.${system};

writeScriptBin "microvm" ''
  #! ${pkgs.runtimeShell} -e

  STATE_DIR=/var/lib/microvms

  while getopts ":h:" arg; do
    echo "getopts arg: $arg $OPTARG"
  done
  echo "rest: $@"
''

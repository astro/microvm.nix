{ nixpkgs, lib, runCommand, mdbook, nixosOptionsDoc }:

let
  microvmDoc = nixosOptionsDoc {
    options = (lib.evalModules {
      modules = [
        ../nixos-modules/microvm/options.nix
      ];
    }).options;
  };

in
runCommand "microvm.nix-doc" {
  nativeBuildInputs = [ mdbook ];
} ''
  cp -r ${../doc} doc
  chmod u+w doc/src
  cp ${microvmDoc.optionsCommonMark} doc/src/microvm-options.md
  ${mdbook}/bin/mdbook build -d $out doc
''

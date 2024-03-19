{ nixpkgs, lib, pkgs, runCommand, mdbook, nixosOptionsDoc }:

let
  microvmDoc = nixosOptionsDoc {
    inherit ((lib.evalModules {
      modules = [
        ../nixos-modules/microvm/options.nix
        { _module.args.pkgs = pkgs; }
      ];
    })) options;
  };

in
runCommand "microvm.nix-doc"
{
  nativeBuildInputs = [ mdbook ];
} ''
  cp -r ${../doc} doc
  chmod u+w doc/src
  cp ${microvmDoc.optionsCommonMark} doc/src/microvm-options.md
  ${mdbook}/bin/mdbook build -d $out doc
''

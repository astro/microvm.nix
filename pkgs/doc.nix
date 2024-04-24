{ nixpkgs, lib, pkgs, runCommand, mdbook, nixosOptionsDoc }:

let
  microvmDoc = nixosOptionsDoc {
    inherit ((lib.evalModules {
      modules = [
        ../nixos-modules/microvm/options.nix
        ({ lib, ... }: {
          # Provide `pkgs` arg to all modules
          config._module.args.pkgs = pkgs;
          # Hide NixOS `_module.args` from nixosOptionsDoc to remain
          # specific to microvm.nix
          options._module.args = lib.mkOption {
            internal = true;
          };
        })
      ];
    })) options;
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

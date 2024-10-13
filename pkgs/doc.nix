{ nixpkgs, lib, pkgs, runCommand, mdbook, nixosOptionsDoc }:

let
  makeOptionsDoc = module: nixosOptionsDoc {
    inherit ((lib.evalModules {
      modules = [
        module
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

    transformOptions = opt: opt // {
      declarations = map (decl:
        let
          root = toString ../.;
          declStr = toString decl;
          declPath = lib.removePrefix root decl;
        in
          if lib.hasPrefix root declStr
          # Rewrite links from ../. in the /nix/store to the source on Github
          then {
            name = "microvm.nix${declPath}";
            url = "https://github.com/astro/microvm.nix/tree/main${declPath}";
          }
          else decl
      ) opt.declarations;
    };
  };

  microvmDoc = makeOptionsDoc ../nixos-modules/microvm/options.nix;

  hostDoc = makeOptionsDoc ../nixos-modules/host/options.nix;

in
runCommand "microvm.nix-doc" {
  nativeBuildInputs = [ mdbook ];
} ''
  cp -r ${../doc} doc
  chmod u+w doc/src
  cp ${microvmDoc.optionsCommonMark} doc/src/microvm-options.md
  cp ${hostDoc.optionsCommonMark} doc/src/host-options.md
  ${mdbook}/bin/mdbook build -d $out doc
''

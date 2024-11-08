# Builds a MicroVM from a flake but takes the hypervisor from the
# local pkgs not from the target flake.
{ self
, lib, stdenv
, writeShellScriptBin
, coreutils, git, nix
}:

writeShellScriptBin "build-microvm" ''
  PATH=${lib.makeBinPath [ coreutils git nix ]}

  if [ $# -lt 1 ]; then
    echo Usage: $0 flakeref#nixos
    exit 1
  fi

  FLAKE=$(echo $1|cut -d "#" -f 1)
  NAME=$(echo $1|cut -d "#" -f 2)
  shift
  ARGS=("$@")

  echo Building a MicroVM runner for NixOS configuration $NAME from Flake $FLAKE
  # --impure so that we can getFlake /nix/store/...
  exec nix build "''${ARGS[@]}" --impure --expr "let
    self = builtins.getFlake \"${self}\";
    pkgs = self.inputs.nixpkgs.legacyPackages.${stdenv.targetPlatform.system};
    flake = builtins.getFlake \"$FLAKE\";
    # The imported NixOS system
    original = flake.nixosConfigurations.\"$NAME\";
    # Customizations to the imported NixOS system
    extended = original.extendModules {
      modules = [ {
        # Override other microvm.nix defaults
        microvm.hypervisor = pkgs.lib.mkForce \"qemu\";
        microvm.shares = pkgs.lib.mkForce [ {
          proto = \"9p\";
          tag = \"ro-store\";
          source = \"/nix/store\";
          mountPoint = \"/nix/.ro-store\";
        } ];
        microvm.volumes = pkgs.lib.mkForce [];
        microvm.writableStoreOverlay = pkgs.lib.mkForce null;
        microvm.interfaces = pkgs.lib.mkForce [ {
          type = \"user\";
          id = \"n\";
          mac = \"02:00:00:00:00:01\";
        } ];
      } ] ++ pkgs.lib.optionals (! original.config ? microvm) [
        # If this NixOS system was not already a MicroVM configuration,
        # add the module.
        self.nixosModules.microvm
      ];
    };
  in self.lib.buildRunner {
    inherit pkgs;
    microvmConfig = {
      inherit (extended.config.networking) hostName;
    } // extended.config.microvm;
    inherit (extended.config.system.build) toplevel;
  }"
''

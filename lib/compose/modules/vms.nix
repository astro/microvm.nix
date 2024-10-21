{ microvm, system, config, lib, ... }:

let
  baseConfig = { config, ... }: {
    microvm = {
      shares = [ {
        proto = "9p";
        tag = "nix-store";
        source = "/nix/store";
        mountPoint = "/nix/store";
      } ];
      socket = "control-${config.networking.hostName}.socket";
    };
  };

  # A base system that is fully evaluated once, and reused with extendModules per VM.
  baseSystem = lib.nixosSystem {
    # TODO: option
    inherit system;

    modules = [
      microvm.nixosModules.microvm
      baseConfig
    ];
  };

in
{
  options.system.microvmConfigs = with lib; mkOption {
    type = with types; attrsOf raw;
    default = {};
    description = ''
      Generated
    '';
    internal = true;
  };

  config.system = {
    microvmConfigs = builtins.mapAttrs (name: { config, ... }:
      (baseSystem.extendModules {
        modules = [
          { networking.hostName = name; }
          config
        ];
      }).config
    ) config.microvm.vms;
  };
}

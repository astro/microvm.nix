{ microvm, system, config, lib, ... }:

let
  baseConfig = { config, ... }: {
    microvm = {
      socket = "control-${config.networking.hostName}.socket";

      shares = [ {
        proto = "9p";
        tag = "store";
        source = "/nix/store";
        mountPoint = "/nix/store";
      } ];
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

  options.system.microvmRunners = with lib; mkOption {
    type = with types; attrsOf package;
    default = {};
    description = ''
      Generated `microvm.declaredRunner`
    '';
    internal = true;
  };

  config.system = {
    microvmConfigs = builtins.mapAttrs (name: { config, ... }:
      (baseSystem.extendModules {
        modules = [ config ];
      }).config
    ) config.microvm.vms;

    microvmRunners = builtins.mapAttrs (name: config:
      builtins.trace "runner: ${name}"
      config.microvm.declaredRunner
    ) config.system.microvmConfigs;
  };
}

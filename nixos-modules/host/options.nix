{ pkgs, lib, ... }:

{
  options.microvm = with lib; {
    host.enable = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Whether to enable the microvm.nix host module.
      '';
    };

    host.useNotifySockets = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Enable if all your MicroVMs run with a Hypervisor that sends
        readiness notification over a VSOCK.

        **Danger!** If one of your MicroVMs doesn't do this, its
        systemd service will not start up successfully!
      '';
    };

    vms = mkOption {
      type = with types; attrsOf (submodule ({ config, name, ... }: {
        options = {
          config = mkOption {
            description = ''
              A specification of the desired configuration of this MicroVM,
              as a NixOS module, for building **without** a flake.
            '';
            default = null;
            type = nullOr (lib.mkOptionType {
              name = "Toplevel NixOS config";
              merge = loc: defs: (import "${config.nixpkgs}/nixos/lib/eval-config.nix" {
                modules =
                  let
                    extraConfig = ({ lib, ... }: {
                      _file = "module at ${__curPos.file}:${toString __curPos.line}";
                      config = {
                        networking.hostName = lib.mkDefault name;
                      };
                    });
                  in [
                    extraConfig
                    ../microvm
                  ] ++ (map (x: x.value) defs);
                prefix = [ "microvm" "vms" name "config" ];
                inherit (config) specialArgs pkgs;
                system = if config.pkgs != null then config.pkgs.system else pkgs.system;
              });
            });
          };

          nixpkgs = mkOption {
            type = types.path;
            default = if config.pkgs != null then config.pkgs.path else pkgs.path;
            defaultText = literalExpression "pkgs.path";
            description = ''
              This option is only respected when `config` is
              specified.

              The nixpkgs path to use for the MicroVM. Defaults to the
              host's nixpkgs.
            '';
          };

          pkgs = mkOption {
            type = types.nullOr types.unspecified;
            default = pkgs;
            defaultText = literalExpression "pkgs";
            description = ''
              This option is only respected when `config` is specified.

              The package set to use for the MicroVM. Must be a
              nixpkgs package set with the microvm overlay. Determines
              the system of the MicroVM.

              If set to null, a new package set will be instantiated.
            '';
          };

          specialArgs = mkOption {
            type = types.attrsOf types.unspecified;
            default = {};
            description = ''
              This option is only respected when `config` is specified.

              A set of special arguments to be passed to NixOS modules.
              This will be merged into the `specialArgs` used to evaluate
              the NixOS configurations.
            '';
          };

          flake = mkOption {
            description = "Source flake for declarative build";
            type = nullOr path;
            default = null;
            defaultText = literalExpression ''flakeInputs.my-infra'';
          };

          updateFlake = mkOption {
            description = "Source flakeref to store for later imperative update";
            type = nullOr str;
            default = null;
            defaultText = literalExpression ''"git+file:///home/user/my-infra"'';
          };

          autostart = mkOption {
            description = "Add this MicroVM to config.microvm.autostart?";
            type = bool;
            default = true;
          };

          restartIfChanged = mkOption {
            type = types.bool;
            default = config.config != null;
            description = ''
              Restart this MicroVM's services if the systemd units are changed,
              i.e. if it has been updated by rebuilding the host.

              Defaults to true for fully-declarative MicroVMs.
            '';
          };
        };
      }));
      default = {};
      description = ''
        The MicroVMs that shall be built declaratively with the host NixOS.
      '';
    };

    stateDir = mkOption {
      type = types.path;
      default = "/var/lib/microvms";
      description = ''
        Directory that contains the MicroVMs
      '';
    };

    autostart = mkOption {
      type = with types; listOf str;
      default = [];
      description = ''
        MicroVMs to start by default.

        This includes declarative `config.microvm.vms` as well as MicroVMs that are managed through the `microvm` command.
      '';
    };
  };
}

{ pkgs, config, lib, ... }:
let
  stateDir = "/var/lib/microvms";
  microvmCommand = import ../pkgs/microvm-command.nix {
    inherit pkgs;
  };
in
{
  options = with lib; {
    microvm.vms = mkOption {
      type = with types; attrsOf (submodule ({ name, ... }: {
        options = {
          flake = mkOption {
            type = nullOr path;
          };
        };
      }));
      default = {};
    };
  };

  config = {
    system.activationScripts.microvm-host = ''
      mkdir -p ${stateDir}
      chown root:kvm ${stateDir}
      chmod g+w ${stateDir}
    '';

    environment.systemPackages = with pkgs; [
      microvmCommand
    ];

    users.users.microvm = {
      isSystemUser = true;
      group = "kvm";
    };

    systemd.services = builtins.foldl' (result: name: result // {
      "install-microvm-${name}" = {
        description = "Install MicroVM '${name}'";
        before = [ "microvm@${name}.service" ];
        wantedBy = [ "microvms.target" ];
        serviceConfig = {
          Type = "oneshot";
        };
        script =
          let
            inherit (config.microvm.vms.${name}) flake;
            runner = flake.packages.${pkgs.system}.${name};
          in
          ''
            mkdir -p ${stateDir}/${name}
            cd ${stateDir}/${name}
            if [ ! -e microvm-run ] || [ ! -e microvm-shutdown ]; then
              ln -sf ${runner}/bin/microvm-run .
              ${if runner.canShutdown
                then "ln -sf ${runner}/bin/microvm-shutdown ."
                else ""}
              echo ${flake} > flake
              # TODO: export interfaces names
              chown -R microvm:kvm .
            fi
          '';
      };
    }) {
      "microvm@" = {
        description = "MicroVM '%i'";
        after = [ "network.target" ];
        unitConfig.ConditionPathExists = "${stateDir}/%i/microvm-run";
        preStart = ''
          rm -f booted
          ln -s $(dirname $(dirname $(readlink microvm-run))) booted
        '';
        postStop = ''
          rm booted
        '';
        serviceConfig = {
          Type = "simple";
          WorkingDirectory = "${stateDir}/%i";
          ExecStart = "${stateDir}/%i/microvm-run";
          ExecStop = "${stateDir}/%i/microvm-shutdown";
          Restart = "always";
          RestartSec = "1s";
          User = "microvm";
          Group = "kvm";
        };
      };
    } (builtins.attrNames config.microvm.vms);

    # Starts all the containers after boot
    systemd.targets.microvms = {
      wantedBy = [ "multi-user.target" ];
      wants = map (name: "microvm@${name}.service")
        (builtins.attrNames config.microvm.vms);
    };
  };
}

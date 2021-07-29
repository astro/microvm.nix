{ pkgs, config, lib, ... }:
let
  stateDir = "/var/lib/microvms";
  microvmCommand = import ../pkgs/microvm-command.nix {
    inherit pkgs;
  };
  user = "microvm";
  group = "kvm";
in
{
  options = with lib; {
    microvm.vms = mkOption {
      type = with types; attrsOf (submodule ({ name, ... }: {
        options = {
          flake = mkOption {
            description = "Source flake for declarative build";
            type = path;
          };
          updateFlake = mkOption {
            description = "Source flake to store for later imperative update";
            type = nullOr str;
            default = null;
          };
        };
      }));
      default = {};
    };
  };

  config = {
    system.activationScripts.microvm-host = ''
      mkdir -p ${stateDir}
      chown ${user}:${group} ${stateDir}
      chmod g+w ${stateDir}
    '';

    environment.systemPackages = with pkgs; [
      microvmCommand
    ];

    users.users.${user} = {
      isSystemUser = true;
      inherit group;
      # allow access to zvol
      extraGroups = [ "disk" ];
    };

    systemd.services = builtins.foldl' (result: name: result // {
      "install-microvm-${name}" = {
        description = "Install MicroVM '${name}'";
        before = [ "microvm@${name}.service" "microvm-tap-interfaces@${name}.service" ];
        wantedBy = [ "microvms.target" ];
        serviceConfig = {
          Type = "oneshot";
        };
        script =
          let
            inherit (config.microvm.vms.${name}) flake updateFlake;
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
              cp ${runner}/share/microvm/tap-interfaces .
            fi

            echo ${if updateFlake != null
                   then updateFlake
                   else flake} > flake
            chown -R ${user}:${group} .
          '';
      };
    }) {
      "microvm-tap-interfaces@" = {
        description = "Setup MicroVM '%i' TAP interfaces";
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStop =
            let
              stopScript = pkgs.writeScript "stop-microvm-tap-interfaces" ''
                #! ${pkgs.runtimeShell} -e

                cd ${stateDir}/$1
                for id in $(cat tap-interfaces); do
                  ${pkgs.iproute2}/bin/ip tuntal del name $id
                done
              '';
            in "${stopScript} %i";
        };
        scriptArgs = "%i";
        script = ''
          cd ${stateDir}/$1
          for id in $(cat tap-interfaces); do
            ${pkgs.iproute2}/bin/ip tuntap add name $id mode tap user ${user}
            ${pkgs.iproute2}/bin/ip link set $id up
          done
        '';
      };

      "microvm@" = {
        description = "MicroVM '%i'";
        requires = [ "microvm-tap-interfaces@%i.service" ];
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
          TimeoutStopSec = 90;
          Restart = "always";
          RestartSec = "1s";
          User = user;
          Group = group;
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

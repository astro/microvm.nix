{ pkgs, config, lib, ... }:
let
  inherit (pkgs) system;
  stateDir = "/var/lib/microvms";
  microvmCommand = import ../pkgs/microvm-command.nix {
    inherit pkgs;
  };
  user = "microvm";
  group = "kvm";
in
{
  options.microvm = with lib; {
    vms = mkOption {
      type = with types; attrsOf (submodule ({ ... }: {
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
        before = [ "microvm@${name}.service" "microvm-tap-interfaces@${name}.service" "microvm-virtiofsd@${name}.service" ];
        partOf = [ "microvm@${name}.service" ];
        wantedBy = [ "microvms.target" ];
        serviceConfig.Type = "oneshot";
        script =
          let
            inherit (config.microvm.vms.${name}) flake updateFlake;
            microvmConfig = flake.nixosConfigurations.${name}.config;
            inherit (microvmConfig.microvm) hypervisor;
            runner = microvmConfig.microvm.runner.${hypervisor};
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
              rm -rf ./virtiofs
              [ -e ${runner}/share/microvm/virtiofs ] && \
                cp -r ${runner}/share/microvm/virtiofs .
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
        before = [ "microvm@%i.service" ];
        partOf = [ "microvm@%i.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStop =
            let
              stopScript = pkgs.writeScript "stop-microvm-tap-interfaces" ''
                #! ${pkgs.runtimeShell} -e

                cd ${stateDir}/$1
                for id in $(cat tap-interfaces); do
                  ${pkgs.iproute2}/bin/ip tuntap del name $id mode tap
                done
              '';
            in "${stopScript} %i";
        };
        scriptArgs = "%i";
        script = ''
          cd ${stateDir}/$1
          for id in $(cat tap-interfaces); do
            if [ -e /sys/class/net/$id ]; then
              ${pkgs.iproute2}/bin/ip tuntap del name $id mode tap
            fi

            ${pkgs.iproute2}/bin/ip tuntap add name $id mode tap user ${user}
            ${pkgs.iproute2}/bin/ip link set $id up
          done
        '';
      };

      "microvm-virtiofsd@" = {
        description = "VirtioFS daemons for MicroVM '%i'";
        before = [ "microvm@%i.service" ];
        after = [ "local-fs.target" ];
        partOf = [ "microvm@%i.service" ];
        unitConfig.ConditionPathExists = "${stateDir}/%i/virtiofs";
        serviceConfig = {
          Type = "forking";
          GuessMainPID = "no";
          WorkingDirectory = "${stateDir}/%i";
          Restart = "always";
          RestartSec = "1s";
        };
        script = ''
          for d in virtiofs/*; do
            SOCKET=$(cat $d/socket)
            SOURCE=$(cat $d/source)
            mkdir -p $SOURCE

            ${pkgs.qemu}/libexec/virtiofsd \
              --socket-path=$SOCKET \
              --socket-group=${config.users.users.microvm.group} \
              -o source=$SOURCE \
              -o cache=none \
              -f &
            disown
          done
        '';
      };

      "microvm@" = {
        description = "MicroVM '%i'";
        requires = [ "microvm-tap-interfaces@%i.service" "microvm-virtiofsd@%i.service" ];
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

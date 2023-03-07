{ pkgs, config, lib, ... }:
let
  stateDir = config.microvm.stateDir;
  microvmCommand = import ../pkgs/microvm-command.nix {
    inherit pkgs;
  };
  user = "microvm";
  group = "kvm";
in
{
  options.microvm = with lib; {
    host.enable = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Whether to enable the microvm.nix host module.
      '';
    };

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
          autostart = mkOption {
            description = "Add this MicroVM to config.microvm.autostart?";
            type = bool;
            default = true;
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

  config = lib.mkIf config.microvm.host.enable {
    system.activationScripts.microvm-host = ''
      mkdir -p ${stateDir}
      chown ${user}:${group} ${stateDir}
      chmod g+w ${stateDir}
    '';

    environment.systemPackages = [
      microvmCommand
    ];

    users.users.${user} = {
      isSystemUser = true;
      inherit group;
      # allow access to zvol
      extraGroups = [ "disk" ];
    };

    security.pam.loginLimits = [
      {
        domain = "${user}";
        item = "memlock";
        type = "hard";
        value = "infinity";
      }
      {
        domain = "${user}";
        item = "memlock";
        type = "soft";
        value = "infinity";
      }
    ];

    systemd.services = builtins.foldl' (result: name: result // {
      "install-microvm-${name}" = {
        description = "Install MicroVM '${name}'";
        before = [
          "microvm@${name}.service"
          "microvm-tap-interfaces@${name}.service"
          "microvm-pci-devices@${name}.service"
          "microvm-virtiofsd@${name}.service"
        ];
        partOf = [ "microvm@${name}.service" ];
        wantedBy = [ "microvms.target" ];
        # only run if /var/lib/microvms/$name does not exist yet
        unitConfig.ConditionPathExists = "!${stateDir}/${name}";
        serviceConfig.Type = "oneshot";
        script =
          let
            inherit (config.microvm.vms.${name}) flake updateFlake;
            microvmConfig = flake.nixosConfigurations.${name}.config;
            runner = microvmConfig.microvm.declaredRunner;
          in
          ''
            mkdir -p ${stateDir}/${name}
            cd ${stateDir}/${name}

            ln -sTf ${runner} current

            echo '${if updateFlake != null
                    then updateFlake
                    else flake}' > flake
            chown -h ${user}:${group} . current flake
          '';
        serviceConfig.SyslogIdentifier = "install-microvm-${name}";
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
                for id in $(cat current/share/microvm/tap-interfaces); do
                  ${pkgs.iproute2}/bin/ip tuntap del name $id mode tap
                done
              '';
            in "${stopScript} %i";
          SyslogIdentifier = "microvm-tap-interfaces@%i";
        };
        unitConfig.ConditionPathExists = "${stateDir}/%i/current/share/microvm/tap-interfaces";
        # `ExecStart`
        scriptArgs = "%i";
        script = ''
          cd ${stateDir}/$1
          for id in $(cat current/share/microvm/tap-interfaces); do
            if [ -e /sys/class/net/$id ]; then
              ${pkgs.iproute2}/bin/ip tuntap del name $id mode tap
            fi

            ${pkgs.iproute2}/bin/ip tuntap add name $id mode tap user ${user}
            ${pkgs.iproute2}/bin/ip link set $id up
          done
        '';
      };

      "microvm-pci-devices@" = {
        description = "Setup MicroVM '%i' devices for passthrough";
        before = [ "microvm@%i.service" ];
        partOf = [ "microvm@%i.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          SyslogIdentifier = "microvm-pci-devices@%i";
        };
        unitConfig.ConditionPathExists = "${stateDir}/%i/current/share/microvm/pci-devices";
        # `ExecStart`
        scriptArgs = "%i";
        script = ''
          cd ${stateDir}/$1

          ${pkgs.kmod}/bin/modprobe vfio-pci

          for path in $(cat current/share/microvm/pci-devices); do
            pushd /sys/bus/pci/devices/$path
            if [ -e driver ]; then
              echo $path > driver/unbind
            fi
            echo vfio-pci > driver_override
            echo $path > /sys/bus/pci/drivers_probe

            # In order to access the vfio dev the permissions must be set
            # for the user/group running the VMM later.
            #
            # Insprired by https://www.kernel.org/doc/html/next/driver-api/vfio.html#vfio-usage-example
            #
            # assert we could get the IOMMU group number (=: name of VFIO dev)
            [[ -e iommu_group ]] || exit 1
            VFIO_DEV=$(basename $(readlink iommu_group))
            echo "Making VFIO device $VFIO_DEV accessible for user"
            chown ${user}:${group} /dev/vfio/$VFIO_DEV
            popd
          done
        '';
      };

      "microvm-virtiofsd@" = rec {
        description = "VirtioFS daemons for MicroVM '%i'";
        before = [ "microvm@%i.service" ];
        after = [ "local-fs.target" ];
        partOf = [ "microvm@%i.service" ];
        unitConfig.ConditionPathExists = "${stateDir}/%i/current/share/microvm/virtiofs";
        serviceConfig = {
          Type = "forking";
          GuessMainPID = "no";
          WorkingDirectory = "${stateDir}/%i";
          Restart = "always";
          RestartSec = "1s";
          SyslogIdentifier = "microvm-virtiofsd@%i";
          LimitNOFILE = 1048576;
        };
        path = with pkgs; [ coreutils virtiofsd ];
        script = ''
          for d in current/share/microvm/virtiofs/*; do
            SOCKET=$(cat $d/socket)
            SOURCE=$(cat $d/source)
            mkdir -p $SOURCE

            virtiofsd \
              --socket-path=$SOCKET \
              --socket-group=${config.users.users.microvm.group} \
              --shared-dir $SOURCE \
              --rlimit-nofile ${toString serviceConfig.LimitNOFILE} \
              --thread-pool-size `nproc` \
              --posix-acl --xattr \
              &
            # detach from shell, but remain in systemd cgroup
            disown
          done
        '';
      };

      "microvm@" = {
        description = "MicroVM '%i'";
        requires = [ "microvm-tap-interfaces@%i.service" "microvm-pci-devices@%i.service" "microvm-virtiofsd@%i.service" ];
        after = [ "network.target" ];
        unitConfig.ConditionPathExists = "${stateDir}/%i/current/bin/microvm-run";
        preStart = ''
          rm -f booted
          ln -s $(readlink current) booted
        '';
        postStop = ''
          rm booted
        '';
        serviceConfig = {
          Type = "simple";
          WorkingDirectory = "${stateDir}/%i";
          ExecStart = "${stateDir}/%i/current/bin/microvm-run";
          ExecStop = "${stateDir}/%i/booted/bin/microvm-shutdown";
          TimeoutStopSec = 90;
          Restart = "always";
          RestartSec = "1s";
          User = user;
          Group = group;
          SyslogIdentifier = "microvm@%i";
          LimitNOFILE = 1048576;
          LimitMEMLOCK = "infinity";
        };
      };
    } (builtins.attrNames config.microvm.vms);

    microvm.autostart = builtins.filter (vmName:
      config.microvm.vms.${vmName}.autostart
    ) (builtins.attrNames config.microvm.vms);
    # Starts all the containers after boot
    systemd.targets.microvms = {
      wantedBy = [ "multi-user.target" ];
      wants = map (name: "microvm@${name}.service") config.microvm.autostart;
    };

    # This creates tap interfaces and attaches them to a bridge for
    # qemu regardless if it is run as root or not.
    security.wrappers.qemu-bridge-helper = lib.mkIf (!config.virtualisation.libvirtd.enable) {
      source = "${pkgs.qemu}/libexec/qemu-bridge-helper";
      owner = "root";
      group = "root";
      capabilities = "cap_net_admin+ep";
    };

    # You must define this file with your bridge interfaces if you
    # intend to use qemu-bridge-helper through a `type = "bridge"`
    # interface.
    environment.etc."qemu/bridge.conf".text = lib.mkDefault ''
      allow all
    '';
  };
}

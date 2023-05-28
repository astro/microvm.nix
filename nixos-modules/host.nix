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
      type = with types; attrsOf (submodule ({ config, name, ... }: {
        options = {
          config = mkOption {
            description = lib.mdDoc ''
              A specification of the desired configuration of this MicroVM,
              as a NixOS module, for building **without** a flake.
            '';
            default = null;
            type = nullOr (lib.mkOptionType {
              name = "Toplevel NixOS config";
              merge = loc: defs: (import "${toString config.pkgs.path}/nixos/lib/eval-config.nix" {
                modules =
                  let
                    extraConfig = {
                      _file = "module at ${__curPos.file}:${toString __curPos.line}";
                      config = {
                        networking.hostName = lib.mkDefault name;
                      };
                    };
                  in [
                    extraConfig
                    ./microvm
                  ] ++ (map (x: x.value) defs);
                prefix = [ "microvm" "vms" name "config" ];
                inherit (config) specialArgs pkgs;
                inherit (config.pkgs) system;
              });
            });
          };

          pkgs = mkOption {
            type = types.unspecified;
            default = pkgs;
            defaultText = literalExpression "pkgs";
            description = lib.mdDoc ''
              This option is only respected when `config` is specified.
              The package set to use for the MicroVM. Must be a nixpkgs package set with the microvm overlay. Determines the system of the MicroVM.
            '';
          };

          specialArgs = mkOption {
            type = types.attrsOf types.unspecified;
            default = {};
            description = lib.mdDoc ''
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

  config = lib.mkIf config.microvm.host.enable {
    assertions = lib.concatMap (vmName: [
      {
        assertion = (config.microvm.vms.${vmName}.flake != null) != (config.microvm.vms.${vmName}.config != null);
        message = "vm ${vmName}: Fully-declarative VMs cannot also set a flake!";
      }
      {
        assertion = (config.microvm.vms.${vmName}.updateFlake != null) != (config.microvm.vms.${vmName}.config != null);
        message = "vm ${vmName}: Fully-declarative VMs cannot set a updateFlake!";
      }
    ]) (builtins.attrNames config.microvm.vms);

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

    systemd.services = builtins.foldl' (result: name: result // (
      let
        microvmConfig = config.microvm.vms.${name};
        inherit (microvmConfig) flake updateFlake;
        isFlake = flake != null;
        guestConfig = if isFlake
                      then flake.nixosConfigurations.${name}.config
                      else microvmConfig.config.config;
        runner = guestConfig.microvm.declaredRunner;
      in
    {
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
        # Only run this if the MicroVM is fully-declarative
        # or /var/lib/microvms/$name does not exist yet.
        unitConfig.ConditionPathExists = lib.mkIf isFlake "!${stateDir}/${name}";
        serviceConfig.Type = "oneshot";
        script = ''
            mkdir -p ${stateDir}/${name}
            cd ${stateDir}/${name}

            ln -sTf ${runner} current
            chown -h ${user}:${group} . current
          ''
          # Including the toplevel here is crucial to have the service definition
          # change when the host is rebuilt and the vm definition changed.
          + lib.optionalString (!isFlake) ''
            ln -sTf ${guestConfig.system.build.toplevel} toplevel
          ''
          # Declarative deployment requires storing just the flake
          + lib.optionalString isFlake ''
            echo '${if updateFlake != null
                    then updateFlake
                    else flake}' > flake
            chown -h ${user}:${group} flake
          '';
        serviceConfig.SyslogIdentifier = "install-microvm-${name}";
      };
      "microvm@${name}" = {
        # restartIfChanged is opt-out, so we have to include the definition unconditionally
        inherit (microvmConfig) restartIfChanged;
        # If the given declarative microvm wants to be restarted on change,
        # We have to make sure this service group is restarted. To make sure
        # that this service is also changed when the microvm configuration changes,
        # we also have to include a trigger here.
        restartTriggers = [guestConfig.system.build.toplevel];
        overrideStrategy = "asDropin";
      };
    })) {
      "microvm-tap-interfaces@" = {
        description = "Setup MicroVM '%i' TAP interfaces";
        before = [ "microvm@%i.service" ];
        partOf = [ "microvm@%i.service" ];
        unitConfig.ConditionPathExists = "${stateDir}/%i/current/share/microvm/tap-interfaces";
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

      "microvm-macvtap-interfaces@" = {
        description = "Setup MicroVM '%i' MACVTAP interfaces";
        before = [ "microvm@%i.service" ];
        partOf = [ "microvm@%i.service" ];
        unitConfig.ConditionPathExists = "${stateDir}/%i/current/share/microvm/macvtap-interfaces";
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStop =
            let
              stopScript = pkgs.writeScript "stop-microvm-tap-interfaces" ''
                #! ${pkgs.runtimeShell} -e
                cd ${stateDir}/$1
                cat current/share/microvm/macvtap-interfaces | while read -r line;do
                  opts=( $line )
                  id="''${opts[0]}"
                  ${pkgs.iproute2}/bin/ip link del name $id
                done
              '';
            in "${stopScript} %i";
          SyslogIdentifier = "microvm-macvtap-interfaces@%i";
        };
        # `ExecStart`
        scriptArgs = "%i";
        script = ''
          cd ${stateDir}/$1
          i=0
          cat current/share/microvm/macvtap-interfaces | while read -r line;do
            opts=( $line )
            id="''${opts[0]}"
            mac="''${opts[1]}"
            link="''${opts[2]}"
            mode="''${opts[3]:+" mode ''${opts[3]}"}"
            if [ -e /sys/class/net/$id ]; then
              ${pkgs.iproute2}/bin/ip link del name $id
            fi
            ${pkgs.iproute2}/bin/ip link add link $link name $id address $mac type macvtap ''${mode[@]}
            ${pkgs.iproute2}/bin/ip link set $id allmulticast on
            echo 1 > /proc/sys/net/ipv6/conf/$id/disable_ipv6
            ${pkgs.iproute2}/bin/ip link set $id up
            ${pkgs.coreutils-full}/bin/chown ${user}:${group} /dev/tap$(< /sys/class/net/$id/ifindex)
          done
        '';
      };


      "microvm-pci-devices@" = {
        description = "Setup MicroVM '%i' devices for passthrough";
        before = [ "microvm@%i.service" ];
        partOf = [ "microvm@%i.service" ];
        unitConfig.ConditionPathExists = "${stateDir}/%i/current/share/microvm/pci-devices";
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          SyslogIdentifier = "microvm-pci-devices@%i";
        };
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
        requires = [
          "microvm-tap-interfaces@%i.service"
          "microvm-macvtap-interfaces@%i.service"
          "microvm-pci-devices@%i.service"
          "microvm-virtiofsd@%i.service"
        ];
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

    # This helper creates tap interfaces and attaches them to a bridge
    # for qemu regardless if it is run as root or not.
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

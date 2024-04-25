{ pkgs, config, lib, ... }:
let
  inherit (config.microvm) stateDir;
  microvmCommand = import ../../pkgs/microvm-command.nix {
    inherit pkgs;
  };
  user = "microvm";
  group = "kvm";
in
{
  imports = [ ./options.nix ];

  config = lib.mkIf config.microvm.host.enable {
    assertions = lib.concatMap (vmName: [
      {
        assertion = config.microvm.vms.${vmName}.config != null -> config.microvm.vms.${vmName}.flake == null;
        message = "vm ${vmName}: Fully-declarative VMs cannot also set a flake!";
      }
      {
        assertion = config.microvm.vms.${vmName}.config != null -> config.microvm.vms.${vmName}.updateFlake == null;
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
        serviceConfig.X-RestartIfChanged = [ "" microvmConfig.restartIfChanged ];
        path = lib.mkForce [];
        # If the given declarative microvm wants to be restarted on change,
        # We have to make sure this service group is restarted. To make sure
        # that this service is also changed when the microvm configuration changes,
        # we also have to include a trigger here.
        restartTriggers = [guestConfig.system.build.toplevel];
        overrideStrategy = "asDropin";
        serviceConfig.Type =
          if guestConfig.microvm.declaredRunner.supportsNotifySocket
          then "notify"
          else "simple";
      };
      "microvm-tap-interfaces@${name}" = {
        serviceConfig.X-RestartIfChanged = [ "" microvmConfig.restartIfChanged ];
        path = lib.mkForce [];
        overrideStrategy = "asDropin";
      };
      "microvm-pci-devices@${name}" = {
        serviceConfig.X-RestartIfChanged = [ "" microvmConfig.restartIfChanged ];
        path = lib.mkForce [];
        overrideStrategy = "asDropin";
      };
      "microvm-virtiofsd@${name}" = {
        serviceConfig.X-RestartIfChanged = [ "" microvmConfig.restartIfChanged ];
        path = lib.mkForce [];
        overrideStrategy = "asDropin";
      };
    })) {
      "microvm-tap-interfaces@" = {
        description = "Setup MicroVM '%i' TAP interfaces";
        before = [ "microvm@%i.service" ];
        partOf = [ "microvm@%i.service" ];
        unitConfig.ConditionPathExists = "${stateDir}/%i/current/share/microvm/tap-interfaces";
        restartIfChanged = false;
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
          TAP_FLAGS="$(cat current/share/microvm/tap-flags)"

          for id in $(cat current/share/microvm/tap-interfaces); do
            if [ -e /sys/class/net/$id ]; then
              ${pkgs.iproute2}/bin/ip tuntap del name $id mode tap $TAP_FLAGS
            fi

            ${pkgs.iproute2}/bin/ip tuntap add name $id mode tap user ${user} $TAP_FLAGS
            ${pkgs.iproute2}/bin/ip link set $id up
          done
        '';
      };

      "microvm-macvtap-interfaces@" = {
        description = "Setup MicroVM '%i' MACVTAP interfaces";
        before = [ "microvm@%i.service" ];
        partOf = [ "microvm@%i.service" ];
        unitConfig.ConditionPathExists = "${stateDir}/%i/current/share/microvm/macvtap-interfaces";
        restartIfChanged = false;
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
        restartIfChanged = false;
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
        restartIfChanged = false;
        serviceConfig = {
          Type = "forking";
          GuessMainPID = "no";
          WorkingDirectory = "${stateDir}/%i";
          Restart = "always";
          RestartSec = "5s";
          SyslogIdentifier = "microvm-virtiofsd@%i";
          LimitNOFILE = 1048576;
        };
        path = with pkgs; [ coreutils virtiofsd ];
        script = ''
          for d in current/share/microvm/virtiofs/*; do
            SOCKET=$(cat $d/socket)
            SOURCE="$(cat $d/source)"
            mkdir -p "$SOURCE"

            virtiofsd \
              --socket-path=$SOCKET \
              --socket-group=${config.users.users.microvm.group} \
              --shared-dir "$SOURCE" \
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
        restartIfChanged = false;
        preStart = ''
          rm -f booted
          ln -s $(readlink current) booted
        '';
        postStop = ''
          rm booted
        '';
        serviceConfig = {
          Type =
            if config.microvm.host.useNotifySockets
            then "notify"
            else "simple";
          WorkingDirectory = "${stateDir}/%i";
          ExecStart = "${stateDir}/%i/current/bin/microvm-run";
          ExecStop = "${stateDir}/%i/booted/bin/microvm-shutdown";
          TimeoutStopSec = 150;
          Restart = "always";
          RestartSec = "5s";
          User = user;
          Group = group;
          SyslogIdentifier = "microvm@%i";
          LimitNOFILE = 1048576;
          NotifyAccess = "all";
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

    # Enable Kernel Same-Page Merging
    hardware.ksm.enable = lib.mkDefault true;
  };
}

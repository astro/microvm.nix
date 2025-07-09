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

    boot.kernelModules = [ "tun" ];

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

    security.pam.loginLimits = [ {
      domain = user;
      item = "memlock";
      type = "hard";
      value = "infinity";
    } {
      domain = user;
      item = "memlock";
      type = "soft";
      value = "infinity";
    } ];

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
        unitConfig.ConditionPathExists = "${stateDir}/%i/current/bin/tap-up";
        restartIfChanged = false;
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          SyslogIdentifier = "microvm-tap-interfaces@%i";
          ExecStart = "${stateDir}/%i/current/bin/tap-up";
          ExecStop = "${stateDir}/%i/booted/bin/tap-down";
        };
      };

      "microvm-macvtap-interfaces@" = {
        description = "Setup MicroVM '%i' MACVTAP interfaces";
        before = [ "microvm@%i.service" ];
        partOf = [ "microvm@%i.service" ];
        unitConfig.ConditionPathExists = "${stateDir}/%i/current/bin/macvtap-up";
        restartIfChanged = false;
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          SyslogIdentifier = "microvm-macvtap-interfaces@%i";
          ExecStart = "${stateDir}/%i/current/bin/macvtap-up";
          ExecStop = "${stateDir}/%i/booted/bin/macvtap-down";
        };
      };


      "microvm-pci-devices@" = {
        description = "Setup MicroVM '%i' devices for passthrough";
        before = [ "microvm@%i.service" ];
        partOf = [ "microvm@%i.service" ];
        unitConfig.ConditionPathExists = "${stateDir}/%i/current/bin/pci-setup";
        restartIfChanged = false;
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          SyslogIdentifier = "microvm-pci-devices@%i";
          ExecStart = "${stateDir}/%i/current/bin/pci-setup";
        };
      };

      "microvm-virtiofsd@" =
        let
          runFromBootedOrCurrent = pkgs.writeShellScript "microvm-runFromBootedOrCurrent" ''
            NAME="$1"
            VM="$2"
            cd "${stateDir}/$VM"

            if [ -e booted ]; then
              exec booted/bin/$NAME
            else
              exec current/bin/$NAME
            fi
          '';

        in {
          description = "VirtioFS daemons for MicroVM '%i'";
          before = [ "microvm@%i.service" ];
          after = [ "local-fs.target" ];
          partOf = [ "microvm@%i.service" ];
          unitConfig.ConditionPathExists = "${stateDir}/%i/current/bin/virtiofsd-run";
          restartIfChanged = false;
          serviceConfig = {
            WorkingDirectory = "${stateDir}/%i";
            ExecStart = "${stateDir}/%i/current/bin/virtiofsd-run";
            ExecReload = "${runFromBootedOrCurrent} virtiofsd-reload %i";
            ExecStop = "${runFromBootedOrCurrent} virtiofsd-shutdown %i";
            LimitNOFILE = 1048576;
            NotifyAccess = "all";
            PrivateTmp = "yes";
            Restart = "always";
            RestartSec = "5s";
            SyslogIdentifier = "microvm-virtiofsd@%i";
            Type = "notify";
          };
        };

      "microvm@" = {
        description = "MicroVM '%i'";
        requires = [
          "microvm-tap-interfaces@%i.service"
          "microvm-macvtap-interfaces@%i.service"
          "microvm-pci-devices@%i.service"
          "microvm-virtiofsd@%i.service"
        ];
        after = [
          "network.target"
          "microvm-tap-interfaces@%i.service"
          "microvm-macvtap-interfaces@%i.service"
          "microvm-pci-devices@%i.service"
          "microvm-virtiofsd@%i.service"
        ];
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
          TimeoutSec = config.microvm.host.startupTimeout; 
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
      source = "${pkgs.qemu-utils}/libexec/qemu-bridge-helper";
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

    # TODO: remove in 2026
    system.activationScripts.microvm-update-check = ''
      if [ -d ${stateDir} ]; then
        _outdated_microvms=""

        for dir in ${stateDir}/*; do
          if [ -e $dir/current/share/microvm/virtiofs ] &&
             [ ! -e $dir/current/bin/virtiofsd-run ]; then
            _outdated_microvms="$_outdated_microvms $(basename $dir)"
          elif [ -e $dir/current/share/microvm/tap-interfaces ] &&
             [ ! -e $dir/current/bin/tap-up ]; then
            _outdated_microvms="$_outdated_microvms $(basename $dir)"
          elif [ -e $dir/current/share/microvm/macvtap-interfaces ] &&
             [ ! -e $dir/current/bin/macvtap-up ]; then
            _outdated_microvms="$_outdated_microvms $(basename $dir)"
          elif [ -e $dir/current/share/microvm/pci-devices ] &&
             [ ! -e $dir/current/bin/pci-setup ]; then
            _outdated_microvms="$_outdated_microvms $(basename $dir)"
          fi
        done

        if [ "$_outdated_microvms" != "" ]; then
          echo "The following MicroVMs must be updated to follow the new virtiofsd/tap/macvtap/pci setup scheme: $_outdated_microvms"
        fi
      fi
    '';
  };
}

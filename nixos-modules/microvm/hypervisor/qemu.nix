{ config, pkgs, lib, ... }:

let
  inherit (pkgs) system;
  inherit (config.microvm) vcpu mem user interfaces shares socket forwardPorts;
  rootDisk = config.system.build.squashfs;

  inherit (import ../../../lib { nixpkgs-lib = pkgs.lib; }) withDriveLetters;
  volumes = withDriveLetters 1 config.microvm.volumes;

  arch = builtins.head (builtins.split "-" system);
  requirePci = shares != [];
  machine = if requirePci
            then "q35"
            else "microvm,x-option-roms=off,isa-serial=off,pit=off,pic=off,rtc=off";
  devType = if requirePci
            then "pci"
            else "device";

  enumerate = n: xs:
    if xs == []
    then []
    else [
      (builtins.head xs // { index = n; })
    ] ++ (enumerate (n + 1) (builtins.tail xs));

  canSandbox =
    # Don't let qemu sandbox itself if it is going to call qemu-bridge-helper
    ! lib.any ({ type, ... }:
      type == "bridge"
    ) config.microvm.interfaces;

  forwardPortsOptions =
      let
        forwardingOptions = lib.flip lib.concatMapStrings forwardPorts
          ({ proto, from, host, guest }:
            if from == "host"
              then "hostfwd=${proto}:${host.address}:${toString host.port}-" +
                   "${guest.address}:${toString guest.port},"
              else "guestfwd=${proto}:${guest.address}:${toString guest.port}-" +
                   "cmd:${pkgs.netcat}/bin/nc ${host.address} ${toString host.port},"
          );
      in
      [
        "${forwardingOptions}"
      ];
in {
  microvm.runner.qemu = import ../../../pkgs/runner.nix {
    inherit config pkgs;

    hypervisor = "qemu";

    command = lib.escapeShellArgs (
      [
        "${pkgs.qemu}/bin/qemu-system-${arch}"
        "-name" "qemu-${config.networking.hostName}"
        "-M" machine
        "-m" (toString mem)
        "-cpu" "host,+x2apic"
        "-smp" (toString vcpu)
        "-no-acpi" "-enable-kvm"
        "-nodefaults" "-no-user-config"
        "-nographic"
        # qemu just hangs after shutdown, allow to exit by rebooting
        "-no-reboot"
        "-serial" "null"
        "-device" "virtio-serial-${devType}"
        "-chardev" "stdio,mux=on,id=virtiocon0,signal=off"
        "-device" "virtconsole,chardev=virtiocon0"
        "-device" "i8042"
        "-device" "virtio-rng-${devType}"
        "-drive" "id=root,format=raw,media=cdrom,file=${rootDisk},if=none,aio=io_uring"
        "-device" "virtio-blk-${devType},drive=root"
        "-kernel" "${config.system.build.kernel.dev}/vmlinux"
        "-append" "console=hvc0 acpi=off reboot=t panic=-1 ${toString config.microvm.kernelParams}"
      ] ++
      lib.optionals canSandbox [
        "-sandbox" "on"
      ] ++
      (if user != null then [ "-user" user ] else []) ++
      (if socket != null then [ "-qmp" "unix:${socket},server,nowait" ] else []) ++
      builtins.concatMap ({ image, letter, ... }:
        [ "-drive" "id=vd${letter},format=raw,file=${image},if=none,aio=io_uring" "-device" "virtio-blk-${devType},drive=vd${letter}" ]
      ) volumes ++
      (if shares != []
       then [
         "-object" "memory-backend-memfd,id=mem,size=${toString mem}M,share=on"
         "-numa" "node,memdev=mem"
       ] ++ (
         builtins.concatMap ({ proto, index, socket, source, tag, ... }: {
           "virtiofs" = [
             "-chardev" "socket,id=fs${toString index},path=${socket}"
             "-device" "vhost-user-fs-${devType},chardev=fs${toString index},tag=${tag}"
           ];
           "9p" = [
             "-fsdev" "local,id=fs${toString index},path=${source},security_model=none"
             "-device" "virtio-9p-${devType},fsdev=fs${toString index},mount_tag=${tag}"
           ];
         }.${proto}) (enumerate 0 shares)
       )
       else []) ++
      (builtins.concatMap ({ type, id, mac, bridge }: [
        "-netdev" (
          lib.concatStringsSep "," ([
            "${type}"
            "id=${id}"
           ]
          ++ (lib.warnIf (type != "user" && forwardPortsOptions != []) "forwardPortsOptions only running with user type" lib.optionals (type == "user" && forwardPorts != []) forwardPortsOptions)
          ++ lib.optionals (type == "bridge") [
            "br=${bridge}" "helper=/run/wrappers/bin/qemu-bridge-helper"
          ] ++ lib.optionals (type == "tap") [
            "ifname=${id}"
            "script=no" "downscript=no"
          ])
        )
        "-device" "virtio-net-${devType},netdev=${id},mac=${mac}"
      ]) interfaces)
    );

    canShutdown = socket != null;

    shutdownCommand =
      if socket != null
      then
        let
          writeQmp = data: ''
          echo '${builtins.toJSON data}'
        '';
        in ''
          (
            ${writeQmp { execute = "qmp_capabilities"; }}
            ${writeQmp {
              execute = "input-send-event";
              arguments.events = [ {
                type = "key";
                data = {
                  down = true;
                  key = {
                    type = "qcode";
                    data = "ctrl";
                  };
                };
              } {
                type = "key";
                data = {
                  down = true;
                  key = {
                    type = "qcode";
                    data = "alt";
                  };
                };
              } {
                type = "key";
                data = {
                  down = true;
                  key = {
                    type = "qcode";
                    data = "delete";
                  };
                };
              } ];
            }}
          ) | \
          ${pkgs.socat}/bin/socat STDIO UNIX:${socket},shut-none
      ''
      else throw "Cannot shutdown without socket";
  };
}

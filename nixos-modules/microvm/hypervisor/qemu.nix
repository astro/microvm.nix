{ config, pkgs, lib, ... }:

let
  inherit (pkgs) system;
  inherit (config.microvm) vcpu mem user interfaces shares socket;
  rootDisk = config.system.build.squashfs;

  inherit (import ../../../lib { nixpkgs-lib = pkgs.lib; }) withDriveLetters;
  volumes = withDriveLetters 1 config.microvm.volumes;

  # interfaces ? [ { id = "eth0"; type = "user"; mac = "00:23:de:ad:be:ef"; } ]

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
        "-drive" "id=root,format=raw,media=cdrom,file=${rootDisk},if=none"
        "-device" "virtio-blk-${devType},drive=root"
        "-kernel" "${config.system.build.kernel.dev}/vmlinux"
        "-append" "console=hvc0 acpi=off reboot=t panic=-1 quiet ro root=/dev/vda init=${config.system.build.toplevel}/init ${toString config.boot.kernelParams}"
        "-sandbox" "on"
      ] ++
      (if user != null then [ "-user" user ] else []) ++
      (if socket != null then [ "-qmp" "unix:${socket},server,nowait" ] else []) ++
      builtins.concatMap ({ image, letter, ... }:
        [ "-drive" "id=vd${letter},format=raw,file=${image},if=none" "-device" "virtio-blk-${devType},drive=vd${letter}" ]
      ) volumes ++
      (if shares != []
       then [
         "-object" "memory-backend-memfd,id=mem,size=${toString mem}M,share=on"
         "-numa" "node,memdev=mem"
       ] ++ (
         builtins.concatMap ({ index, socket, tag, ... }: [
           "-chardev" "socket,id=fs${toString index},path=${socket}"
           "-device" "vhost-user-fs-${devType},chardev=fs${toString index},tag=${tag}"
         ]) (enumerate 0 shares)
       )
       else []) ++
      (builtins.concatMap ({ type, id, mac }: [
        "-netdev" "${type},id=${id}${lib.optionalString (type == "tap") ",ifname=${id},script=no,downscript=no"}"
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

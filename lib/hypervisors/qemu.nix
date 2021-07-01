{ self, nixpkgs }:

{ system
, vcpu
, mem
, nixos
, append
, user ? null
, interfaces ? [ { id = "eth0"; type = "user"; mac = "00:23:de:ad:be:ef"; } ]
, rootDisk
, volumes
, hostName
, socket ? "/tmp/microvm-${hostName}.qmp"
, ...
}@args:
let
  config = args // {
    inherit interfaces user;
  };
  pkgs = nixpkgs.legacyPackages.${system};
  arch = builtins.head (builtins.split "-" system);
in config // {
  command = nixpkgs.lib.escapeShellArgs (
    [
      "${pkgs.qemu}/bin/qemu-system-${arch}"
      "-name" "qemu-${hostName}"
      "-M" "microvm,x-option-roms=off,isa-serial=off,pit=off,pic=off,rtc=off"
      "-m" (toString mem)
      "-cpu" "host,+x2apic"
      "-smp" (toString vcpu)
      "-no-acpi" "-enable-kvm"
      "-nodefaults" "-no-user-config"
      "-nographic" "-no-reboot"
      "-device" "virtio-serial-device"
      "-device" "i8042"
      "-chardev" "stdio,id=virtiocon0"
      "-device" "virtconsole,chardev=virtiocon0"
      "-device" "virtio-rng-device"
      "-drive" "id=root,format=raw,media=cdrom,file=${rootDisk},if=none" "-device" "virtio-blk-device,drive=root"
      "-kernel" "${nixos.config.system.build.kernel.dev}/vmlinux"
      "-append" "console=hvc0 acpi=off reboot=t panic=-1 quiet ro root=/dev/vda init=${nixos.config.system.build.toplevel}/init ${append}"
      "-sandbox" "on"
    ] ++
    (if user != null then [ "-user" user ] else []) ++
    (if socket != null then [ "-qmp" "unix:${socket},server,nowait" ] else []) ++
    builtins.concatMap ({ image, letter, ... }:
      [ "-drive" "id=vd${letter},format=raw,file=${image},if=none" "-device" "virtio-blk-device,drive=vd${letter}" ]
    ) (config.volumes) ++
    (builtins.concatMap ({ type, id, mac }: [
      "-netdev" "${type},id=${id}"
      "-device" "virtio-net-device,netdev=${id},mac=${mac}"
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
        ${pkgs.socat}/bin/socat STDIO UNIX:${socket}
    ''
    else throw "Cannot shutdown without socket";
}

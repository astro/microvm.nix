{ self, nixpkgs }:

{ system
, vcpu
, mem
, nixos
, append
, user ? null
, interfaces ? [ { id = "eth0"; type = "user"; mac = "00:23:de:ad:be:ef"; } ]
, rootDisk
, volumes ? []
, shares ? []
, hostName
, socket ? "microvm-${hostName}.qmp"
, ...
}@args:
let
  pkgs = nixpkgs.legacyPackages.${system};

  config = args // {
    inherit interfaces user;
  };
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

in config // {
  command = nixpkgs.lib.escapeShellArgs (
    [
      "${pkgs.qemu}/bin/qemu-system-${arch}"
      "-name" "qemu-${hostName}"
      "-M" machine
      "-m" (toString mem)
      "-cpu" "host,+x2apic"
      "-smp" (toString vcpu)
      "-no-acpi" "-enable-kvm"
      "-nodefaults" "-no-user-config"
      "-nographic" "-no-reboot"
      "-device" "virtio-serial-${devType}"
      "-device" "i8042"
      "-chardev" "stdio,id=virtiocon0"
      "-device" "virtconsole,chardev=virtiocon0"
      "-device" "virtio-rng-${devType}"
      "-drive" "id=root,format=raw,media=cdrom,file=${rootDisk},if=none"
      "-device" "virtio-blk-${devType},drive=root"
      "-kernel" "${nixos.config.system.build.kernel.dev}/vmlinux"
      "-append" "console=hvc0 acpi=off reboot=t panic=-1 quiet ro root=/dev/vda init=${nixos.config.system.build.toplevel}/init ${append}"
      "-sandbox" "on"
    ] ++
    (if user != null then [ "-user" user ] else []) ++
    (if socket != null then [ "-qmp" "unix:${socket},server,nowait" ] else []) ++
    builtins.concatMap ({ image, letter, ... }:
      [ "-drive" "id=vd${letter},format=raw,file=${image},if=none" "-device" "virtio-blk-${devType},drive=vd${letter}" ]
    ) (config.volumes) ++
    (if config.volumes != []
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
      "-netdev" "${type},id=${id}${nixpkgs.lib.optionalString (type == "tap") ",ifname=${id},script=no,downscript=no"}"
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
}

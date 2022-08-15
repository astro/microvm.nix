{ pkgs
, microvmConfig
, kernel
, rootDisk
}:

let
  inherit (pkgs) lib system;

  qemu =
    if lib.any ({ bus, ... }: bus == "usb") microvmConfig.devices
    then pkgs.qemu_kvm.overrideAttrs (oa: {
      configureFlags = oa.configureFlags ++ [
        "--enable-libusb"
      ];
      buildInputs = oa.buildInputs ++ (with pkgs; [
        libusb
      ]);
    })
    else pkgs.qemu_kvm;

  inherit (microvmConfig) hostName vcpu mem user interfaces shares socket forwardPorts devices;
  inherit (microvmConfig.qemu) extraArgs;

  inherit (import ../. { nixpkgs-lib = pkgs.lib; }) withDriveLetters;
  volumes = withDriveLetters 1 microvmConfig.volumes;

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
    ) microvmConfig.interfaces;

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
      [ forwardingOptions ];
in {
  hypervisor = "qemu";

  command = lib.escapeShellArgs (
    [
      "${qemu}/bin/qemu-system-${arch}"
      "-name" hostName
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
      "-kernel" "${kernel.dev}/vmlinux"
      "-append" "console=hvc0 acpi=off reboot=t panic=-1 ${toString microvmConfig.kernelParams}"
    ] ++
    lib.optionals canSandbox [
      "-sandbox" "on"
    ] ++
    lib.optionals (user != null) [ "-user" user ] ++
    lib.optionals (socket != null) [ "-qmp" "unix:${socket},server,nowait" ] ++
    builtins.concatMap ({ image, letter, ... }:
      [ "-drive" "id=vd${letter},format=raw,file=${image},if=none,aio=io_uring" "-device" "virtio-blk-${devType},drive=vd${letter}" ]
    ) volumes ++
    lib.optionals (shares != []) (
      [
        "-object" "memory-backend-memfd,id=mem,size=${toString mem}M,share=on"
        "-numa" "node,memdev=mem"
      ] ++
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
    ++
    lib.warnIf (
      forwardPorts != [] &&
      ! builtins.any ({ type, ... }: type == "user") interfaces
    ) "${hostName}: forwardPortsOptions only running with user network" (
      builtins.concatMap ({ type, id, mac, bridge }: [
        "-netdev" (
          lib.concatStringsSep "," (
            [
              "${type}"
              "id=${id}"
            ]
            ++ lib.optionals (type == "user" && forwardPortsOptions != []) forwardPortsOptions
            ++ lib.optionals (type == "bridge") [
              "br=${bridge}" "helper=/run/wrappers/bin/qemu-bridge-helper"
            ]
            ++ lib.optionals (type == "tap") [
              "ifname=${id}"
              "script=no" "downscript=no"
            ]
          )
        )
        "-device" "virtio-net-${devType},netdev=${id},mac=${mac}"
      ]) interfaces
    )
    ++
    lib.optionals (lib.any ({ bus, ... }:
      bus == "usb"
    ) devices) [
      "-usb"
      "-device" "usb-ehci"
    ]
    ++
    builtins.concatMap ({ bus, path, ... }: {
      pci = [
        "-device" "vfio-pci,host=${path},multifunction=on"
      ];
      usb = [
        "-device" "usb-host,${path}"
      ];
    }.${bus}) devices
    ++
    extraArgs
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

            # wait for exit
            cat
          ) | \
          ${pkgs.socat}/bin/socat STDIO UNIX:${socket},shut-none
      ''
    else throw "Cannot shutdown without socket";
}

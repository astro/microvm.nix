{ pkgs
, microvmConfig
, kernel
, bootDisk
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

  inherit (microvmConfig) hostName vcpu mem balloonMem user interfaces shares socket forwardPorts devices;
  inherit (microvmConfig.qemu) extraArgs;

  inherit (import ../. { nixpkgs-lib = pkgs.lib; }) withDriveLetters;
  volumes = withDriveLetters 1 microvmConfig.volumes;

  arch = builtins.head (builtins.split "-" system);
  # PCI required by vfio-pci for PCI passthrough
  pciInDevices = lib.any ({ bus, ... }: bus == "pci") devices;
  requirePci = shares != [] || pciInDevices;
  machine = {
    x86_64-linux =
      if requirePci
      then "q35,accel=kvm:tcg,mem-merge=on,sata=off"
      else "microvm,accel=kvm:tcg,x-option-roms=off,pit=off,pic=off,rtc=off,mem-merge=on";
    aarch64-linux = "virt,gic-version=max,accel=kvm:tcg";
  }.${system};
  devType = if requirePci
            then "pci"
            else "device";
  kernelPath = {
    x86_64-linux = "${kernel.dev}/vmlinux";
    aarch64-linux = "${kernel.out}/${pkgs.stdenv.hostPlatform.linux-kernel.target}";
  }.${system};

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

  writeQmp = data: ''
    echo '${builtins.toJSON data}'
  '';
in {
  hypervisor = "qemu";

  command = lib.escapeShellArgs (
    [
      "${qemu}/bin/qemu-system-${arch}"
      "-name" hostName
      "-M" machine
      "-m" (toString (mem + balloonMem))
      "-smp" (toString vcpu)
      "-enable-kvm"
      "-nodefaults" "-no-user-config"
      "-nographic"
      # qemu just hangs after shutdown, allow to exit by rebooting
      "-no-reboot"
      "-chardev" "stdio,mux=on,id=con0,signal=off"
      "-serial" "chardev:con0"
      "-chardev" "pty,id=con1"
      "-device" "virtio-serial-${devType}"
      "-device" "virtconsole,chardev=con1"
      "-device" "virtio-rng-${devType}"
      "-drive" "id=root,format=raw,read-only=on,file=${bootDisk},if=none,aio=io_uring"
      "-device" "virtio-blk-${devType},drive=root${lib.optionalString (devType == "pci") ",disable-legacy=on"}"
      "-kernel" "${kernelPath}"
      # hvc1 precedes hvc0 so that nixos starts serial-agetty@ on both
      # without further config
      "-append" "console=hvc0 earlyprintk=ttyS0 console=ttyS0 reboot=t panic=-1 ${toString microvmConfig.kernelParams}"
    ] ++
    lib.optionals (system == "x86_64-linux") [
      "-cpu" "host,+x2apic"
      "-device" "i8042"
      "-bios" "${pkgs.qboot}/bios.bin"
    ] ++
    lib.optionals (system == "aarch64-linux") [
      "-cpu" "host"
    ] ++
    lib.optionals canSandbox [
      "-sandbox" "on"
    ] ++
    lib.optionals (user != null) [ "-user" user ] ++
    lib.optionals (socket != null) [ "-qmp" "unix:${socket},server,nowait" ] ++
    lib.optionals (balloonMem > 0) [ "-device" "virtio-balloon" ] ++
    builtins.concatMap ({ image, letter, ... }:
      [ "-drive" "id=vd${letter},format=raw,file=${image},if=none,aio=io_uring,discard=unmap" "-device" "virtio-blk-${devType},drive=vd${letter}" ]
    ) volumes ++
    lib.optionals (shares != []) (
      [
        "-object" "memory-backend-memfd,id=mem,size=${toString (mem + balloonMem)}M,share=on"
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
      ''
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

  getConsoleScript =
    if socket != null
    then ''
      PTY=$( (
        ${writeQmp { execute = "qmp_capabilities"; }}
        ${writeQmp { execute = "query-chardev"; }}
      ) | \
        ${pkgs.socat}/bin/socat STDIO UNIX:${socket},shut-none | \
        tail -n 1 | \
        ${pkgs.jq}/bin/jq -r '.return | .[] | select(.label == "con0") | .filename' \
      )
      if [[ $PTY =~ ^pty:(.+)$ ]]; then
        PTY="''${BASH_REMATCH[1]}"
      else
        echo "No valid pty opened by qemu" >&2
        exit 1
      fi
    ''
    else null;

  setBalloonScript =
    if socket != null
    then ''
      VALUE=$(( $SIZE * 1024 * 1024 ))
      SIZE=$( (
        ${writeQmp { execute = "qmp_capabilities"; }}
        ${writeQmp { execute = "balloon"; arguments.value = 987; }}
      ) | sed -e s/987/$VALUE/ | \
        ${pkgs.socat}/bin/socat STDIO UNIX:${socket},shut-none | \
        tail -n 1 | \
        ${pkgs.jq}/bin/jq -r .data.actual \
      )
      echo $(( $SIZE / 1024 / 1024 ))
    ''
    else null;
}

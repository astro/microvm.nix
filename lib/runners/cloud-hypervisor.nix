{ pkgs
, microvmConfig
, macvtapFds
}:

let
  inherit (pkgs) lib;
  inherit (microvmConfig) vcpu mem balloonMem user interfaces volumes shares socket devices hugepageMem graphics storeDisk storeOnDisk kernel initrdPath;

  kernelPath = {
    x86_64-linux = "${kernel.dev}/vmlinux";
    aarch64-linux = "${kernel.out}/${pkgs.stdenv.hostPlatform.linux-kernel.target}";
  }.${pkgs.system};

  # balloon
  useBallooning = balloonMem > 0;

  # Transform attrs to parameters in form of `key1=value1,key2=value2,[...]`
  opsMapped = ops: lib.concatStringsSep "," (lib.mapAttrsToList (k: v: "${k}=${v}") ops);

  # Attrs representing CHV mem options
  memOps = opsMapped ({
    size = "${toString mem}M";
    mergeable = "on";
    shared = "on";
  }
  # add ballooning options and override 'size' key
  // lib.optionalAttrs useBallooning {
    size = "${toString (mem + balloonMem)}M";
    hotplug_method = "virtio-mem";
    hotplug_size = "${toString balloonMem}M";
    hotplugged_size = "${toString balloonMem}M";
  }
  # enable hugepages (shared option is ignored by CHV)
  // lib.optionalAttrs hugepageMem {
    hugepages = "on";
  });

  balloonOps = opsMapped {
    size = "${toString balloonMem}M";
    deflate_on_oom = "on";
    free_page_reporting = "on";
  };

  # cloud-hypervisor >= 30.0 has a new command-line arguments syntax
  hasNewArgSyntax = builtins.compareVersions pkgs.cloud-hypervisor.version "30.0" >= 0;
  arg =
    if hasNewArgSyntax
    then switch: params:
      # `--switch param0 --switch param1 ...`
      builtins.concatMap (param: [ switch param ]) params
    else switch: params:
      # `` or `--switch param0 param1 ...`
      lib.optionals (params != []) (
        [ switch ] ++ params
      );

  gpuParams = {
    context-types = "virgl:virgl2:cross-domain";
    displays = [ {
      hidden = true;
    } ];
    egl = true;
    vulkan = true;
  };

in {
  preStart = ''
    ${microvmConfig.preStart}
    ${lib.optionalString (socket != null) ''
      # workaround cloud-hypervisor sometimes
      # stumbling over a preexisting socket
      rm -f '${socket}'
    ''}
  '' + lib.optionalString graphics.enable ''
    rm -f ${graphics.socket}
    ${pkgs.crosvm}/bin/crosvm device gpu \
      --socket ${graphics.socket} \
      --wayland-sock $XDG_RUNTIME_DIR/$WAYLAND_DISPLAY \
      --params '${builtins.toJSON gpuParams}' \
      &
    while ! [ -S ${graphics.socket} ]; do
      sleep .1
    done
  '';

  command =
    if user != null
    then throw "cloud-hypervisor will not change user"
    else lib.escapeShellArgs (
      [
        (if graphics.enable
         then "${pkgs.cloud-hypervisor-graphics}/bin/cloud-hypervisor"
         else "${pkgs.cloud-hypervisor}/bin/cloud-hypervisor"
        )
        "--cpus" "boot=${toString vcpu}"
        "--watchdog"
        "--console" "null"
        "--serial" "tty"
        "--kernel" kernelPath
        "--initramfs" initrdPath
        "--cmdline" "console=ttyS0 reboot=t panic=-1 ${toString microvmConfig.kernelParams}"
        "--seccomp" "true"
        "--memory" memOps
      ]
      ++
      lib.optionals graphics.enable [
        "--gpu" "socket=${graphics.socket}"
      ]
      ++
      lib.optionals useBallooning [ "--balloon" balloonOps ]
      ++
      arg "--disk" (
        lib.optional storeOnDisk "path=${storeDisk},readonly=on"
        ++
        map ({ image, ... }: "path=${image}") volumes
      )
      ++
      arg "--fs" (map ({ proto, socket, tag, ... }:
        if proto == "virtiofs"
        then "tag=${tag},socket=${socket}"
        else throw "cloud-hypervisor supports only shares that are virtiofs"
      ) shares)
      ++
      lib.optionals (socket != null) [ "--api-socket" socket ]
      ++
      arg "--net" (map ({ type, id, mac, ... }:
        if type == "tap"
        then "tap=${id},mac=${mac}"
        else if type == "macvtap"
        then "fd=${toString macvtapFds.${id}},mac=${mac}"
        else throw "Unsupported interface type ${type} for Cloud-Hypervisor"
      ) interfaces)
      ++
      arg "--device" (map ({ bus, path }: {
        pci = "path=/sys/bus/pci/devices/${path}";
        usb = throw "USB passthrough is not supported on cloud-hypervisor";
      }.${bus}) devices)
    );

  canShutdown = socket != null;

  shutdownCommand =
    if socket != null
    then ''
        api() {
          ${pkgs.curl}/bin/curl \
            --unix-socket ${socket} \
            $@
        }

        api -X PUT http://localhost/api/v1/vm.power-button

        ${pkgs.util-linux}/bin/waitpid $MAINPID
      ''
    else throw "Cannot shutdown without socket";

  getConsoleScript =
    if socket != null
    then ''
      PTY=$(${pkgs.cloud-hypervisor}/bin/ch-remote --api-socket ${socket} info | \
        ${pkgs.jq}/bin/jq -r .config.serial.file \
      )
    ''
    else null;

  setBalloonScript =
    if socket != null
    then ''
      ${pkgs.cloud-hypervisor}/bin/ch-remote --api-socket ${socket} resize --balloon $SIZE"M"
    ''
    else null;

  requiresMacvtapAsFds = true;
}

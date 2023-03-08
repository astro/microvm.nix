{ pkgs
, lib
, microvmConfig
, kernel
, bootDisk
}:

let
  inherit (pkgs) lib;
  inherit (microvmConfig) vcpu mem balloonMem user interfaces volumes shares socket devices hugepageMem;

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

in {
  preStart = ''
    ${microvmConfig.preStart}
    ${lib.optionalString (socket != null) ''
      # workaround cloud-hypervisor sometimes
      # stumbling over a preexisting socket
      rm -f '${socket}'
    ''}
  '';

  command =
    if user != null
    then throw "cloud-hypervisor will not change user"
    else lib.escapeShellArgs (
      [
        "${pkgs.cloud-hypervisor}/bin/cloud-hypervisor"
        "--cpus" "boot=${toString vcpu}"
        "--watchdog"
        "--console" "tty"
        "--serial" "pty"
        "--kernel" "${kernel.dev}/vmlinux"
        "--cmdline" "console=hvc0 console=ttyS0 reboot=t panic=-1 ${toString microvmConfig.kernelParams}"
        "--seccomp" "true"
        "--memory" memOps
      ]
      ++ 
      lib.optionals useBallooning [ "--balloon" balloonOps ]
      ++
      [ "--disk" "path=${bootDisk},readonly=on" ]
      ++
      map ({ image, ... }:
        "path=${image}"
      ) volumes
      ++
      lib.optionals (shares != []) (
        [ "--fs" ] ++
        map ({ proto, socket, tag, ... }:
          if proto == "virtiofs"
          then "tag=${tag},socket=${socket}"
          else throw "cloud-hypervisor supports only shares that are virtiofs"
        ) shares
      )
      ++
      lib.optionals (socket != null) [ "--api-socket" socket ]
      ++
      lib.optionals (interfaces != []) (
        [ "--net" ] ++
        map ({ type, id, mac, ... }:
          if type == "tap"
          then "tap=${id},mac=${mac}"
          else throw "Unsupported interface type ${type} for Cloud-Hypervisor"
        ) interfaces
      )
      ++
      lib.optionals (devices != []) (
        [ "--device" ] ++
        map ({ bus, path }: {
          pci = "path=/sys/bus/pci/devices/${path}";
          usb = throw "USB passthrough is not supported on cloud-hypervisor";
        }.${bus}) devices
      )
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

        # wait for exit
        ${pkgs.socat}/bin/socat STDOUT UNIX:${socket},shut-none
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
}

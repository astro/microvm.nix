{ pkgs
, microvmConfig
, macvtapFds
}:

let
  inherit (pkgs) lib system;
  inherit (microvmConfig) vcpu mem balloonMem user interfaces volumes shares socket devices hugepageMem graphics storeDisk storeOnDisk kernel initrdPath;
  inherit (microvmConfig.cloud-hypervisor) extraArgs systemExecutable;

  cloud-hypervisor =
    if graphics.enable then pkgs.cloud-hypervisor-graphics else pkgs.cloud-hypervisor;

  # Removes references to $out from the PATH to see if a security wrapper is
  # installed
  cloud-hypervisor-shim =
    pkgs.runCommand "cloud-hypervisor-shim" { meta.mainProgram = "cloud-hypervisor"; }
      (
        ''
          mkdir -p $out/bin
          cat << EOF > "$out/bin/cloud-hypervisor"
          #!${lib.getExe pkgs.bash}

          set -e

          # Inhibit the shim if it's in the PATH

          new_PATH=
          while IFS=: read -r -d ":" path ; do
            if [[ "\$path" = *"$out"* ]] ; then
              continue
            fi
            if [[ "\$new_PATH" == "" ]] ; then
              new_PATH="\$path"
            else
              new_PATH="\$new_PATH:\$path"
            fi
          done <<< "\$PATH"
          export PATH="\$new_PATH"

          path="\$(type cloud-hypervisor 2>/dev/null)" \
            || path=${lib.getExe cloud-hypervisor}
          path="\''${path#cloud-hypervisor is }"

          if [[ "\$path" == *"$out"* ]] ; then
            echo "cloud-hypervisor-shim: sanity check failed, couldn't remove the shim from PATH" >&2
            exit 1
          fi

        ''
        + lib.optionalString systemExecutable.versionCheck ''
          foundVersion="\$("\$path" --version)"
          foundVersion="\''${foundVersion#cloud-hypervisor }"
          foundVersion="\''${foundVersion#v}"
          expectedVersion="${lib.getVersion cloud-hypervisor}"
          if [[ "\$foundVersion" != "\$expectedVersion"* ]]; then
            echo "cloud-hypervisor-shim: sanity check failed, system \
          cloud-hypervisor (\$foundVersion) doesn't match the expected version \
          (\$expectedVersion). Try disabling \
          microvm.cloud-hypervisor.systemExecutable.versionCheck or updating the \
          host system" >&2
            exit 1
          fi
        ''
        + ''

          exec -a cloud-hypervisor "\$path" "\$@"
          EOF
          chmod a+x "$out/bin/cloud-hypervisor"
        ''
      );

  kernelPath = {
    x86_64-linux = "${kernel.dev}/vmlinux";
    aarch64-linux = "${kernel.out}/${pkgs.stdenv.hostPlatform.linux-kernel.target}";
  }.${pkgs.system};

  kernelConsole =
    if system == "x86_64-linux"
    then "earlyprintk=ttyS0 console=ttyS0"
    else if system == "aarch64-linux"
    then "console=ttyAMA0"
    else "";

  # balloon
  useBallooning = balloonMem > 0;

  useVirtiofs = builtins.any ({ proto, ... }: proto == "virtiofs") shares;

  # Transform attrs to parameters in form of `key1=value1,key2=value2,[...]`
  opsMapped = ops: lib.concatStringsSep "," (lib.mapAttrsToList (k: v: "${k}=${v}") ops);

  # Attrs representing CHV mem options
  memOps = opsMapped ({
    size = "${toString mem}M";
    mergeable = "on";
    # Shared memory is required for usage with virtiofsd but it
    # prevents Kernel Same-page Merging.
    shared = if useVirtiofs || graphics.enable then "on" else "off";
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

  tapMultiQueue = vcpu > 1;

  # Multi-queue options
  mqOps = lib.optionalAttrs tapMultiQueue {
    num_queues = toString vcpu;
  };

  # cloud-hypervisor >= 30.0 < 36.0 temporarily replaced clap with argh
  hasArghSyntax =
    builtins.compareVersions pkgs.cloud-hypervisor.version "30.0" >= 0 &&
    builtins.compareVersions pkgs.cloud-hypervisor.version "36.0" < 0;
  arg =
    if hasArghSyntax
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
  inherit tapMultiQueue;

  preStart = ''
    ${microvmConfig.preStart}
    ${lib.optionalString (socket != null) ''
      # workaround cloud-hypervisor sometimes
      # stumbling over a preexisting socket
      rm -f '${socket}'
    ''}


    # Ensure notify sockets are removed if cloud-hypervisor didn't exit cleanly the last time
    rm -f notify.vsock notify.vsock_8888

    # Start socat to forward systemd notify socket over vsock
    if [ -n "$NOTIFY_SOCKET" ]; then
      ${pkgs.socat}/bin/socat UNIX-LISTEN:notify.vsock_8888,fork UNIX-SENDTO:$NOTIFY_SOCKET &
    fi
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

  supportsNotifySocket = true;

  command =
    if user != null
    then throw "cloud-hypervisor will not change user"
    else lib.escapeShellArgs (
      [
        (lib.getExe (
          if microvmConfig.cloud-hypervisor.systemExecutable.enable then
            cloud-hypervisor-shim
          else
            cloud-hypervisor
        ))
        "--cpus" "boot=${toString vcpu}"
        "--watchdog"
        "--console" "null"
        "--serial" "tty"
        "--kernel" kernelPath
        "--initramfs" initrdPath
        "--cmdline" "${kernelConsole} reboot=t panic=-1 ${toString microvmConfig.kernelParams}"
        "--seccomp" "true"
        "--memory" memOps
        "--platform" "oem_strings=[io.systemd.credential:vmm.notify_socket=vsock-stream:2:8888]"
        "--vsock" "cid=3,socket=notify.vsock"
      ]
      ++
      lib.optionals graphics.enable [
        "--gpu" "socket=${graphics.socket}"
      ]
      ++
      lib.optionals useBallooning [ "--balloon" balloonOps ]
      ++
      arg "--disk" (
        lib.optional storeOnDisk (opsMapped ({
          path = toString storeDisk;
          readonly = "on";
        } // mqOps))
        ++
        map ({ image, ... }: (opsMapped ({
          path = toString image;
        } // mqOps))) volumes
      )
      ++
      arg "--fs" (map ({ proto, socket, tag, ... }:
        if proto == "virtiofs"
        then opsMapped {
          inherit tag socket;
        }
        else throw "cloud-hypervisor supports only shares that are virtiofs"
      ) shares)
      ++
      lib.optionals (socket != null) [ "--api-socket" socket ]
      ++
      arg "--net" (map ({ type, id, mac, ... }:
        if type == "tap"
        then opsMapped ({
          tap = id;
          inherit mac;
        } // lib.optionalAttrs tapMultiQueue {
          num_queues = toString (2 * vcpu);
        })
        else if type == "macvtap"
        then opsMapped ({
          fd = "[${lib.concatMapStringsSep "," toString macvtapFds.${id}}]";
          inherit mac;
        } // lib.optionalAttrs tapMultiQueue {
          num_queues = toString (2 * vcpu);
        })
        else throw "Unsupported interface type ${type} for Cloud-Hypervisor"
      ) interfaces)
      ++
      arg "--device" (map ({ bus, path }: {
        pci = "path=/sys/bus/pci/devices/${path}";
        usb = throw "USB passthrough is not supported on cloud-hypervisor";
      }.${bus}) devices)
      ++
      extraArgs
    );

  canShutdown = socket != null;

  shutdownCommand =
    if socket != null
    then ''
        api() {
          ${pkgs.curl}/bin/curl -s \
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

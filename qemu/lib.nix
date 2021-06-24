{ self, nixpkgs }:

{
  runQemu = { system
            , vcpu ? 1
            , mem ? 512
            , nixos
            , append ? ""
            , user ? null
            , interfaces ? [ { id = "eth0"; type = "user"; } ]
            , shared ? []
            , preStart ? ""
            }:
    let
      inherit (nixos.config.networking) hostName;
      pkgs = nixpkgs.legacyPackages.${system};
      arch = builtins.head (builtins.split "-" system);
      rootfs = nixos.config.system.build.toplevel;
      vmTools = pkgs.callPackage ../vmtools.nix { rootModules = []; };
      initrd = "${vmTools.initrd}/initrd"; #nixos.config.system.boot.loader.initrdFile;
      qemuCommand = nixpkgs.lib.escapeShellArgs ([
        "${pkgs.qemu}/bin/qemu-system-${arch}"
        "-name" "qemu-${hostName}"
        "-M" "microvm,x-option-roms=off,isa-serial=off,rtc=off"
        "-m" (builtins.toString mem)
        "-cpu" "host"
        "-smp" (builtins.toString vcpu)
        "-no-acpi" "-enable-kvm"
        "-nodefaults" "-no-user-config"
        "-nographic"
        "-device" "virtio-serial-device"
        "-chardev" "stdio,id=virtiocon0"
        "-device" "virtconsole,chardev=virtiocon0"
        "-device" "virtio-rng-device"
        "-kernel" "${self.packages.${system}.virtioKernel}/bzImage"
        "-initrd" "${initrd}"
        "-fsdev" "local,id=root,path=${rootfs},security_model=passthrough,readonly=on"
        "-device" "virtio-9p-device,fsdev=root,mount_tag=/dev/root"
        "-fsdev" "local,id=store,path=/nix/store,security_model=passthrough,readonly=on"
        "-device" "virtio-9p-device,fsdev=store,mount_tag=store"
        "-append" "console=hvc0 acpi=off reboot=t panic=-1 quiet rootfstype=9p rootflags=trans=virtio ro init=/init command=${rootfs}/init ${append}"
        "-sandbox" "on"
      ] ++
      (if user != null then [ "-user" user ] else []) ++
      (builtins.concatMap ({ type, id, mac }: [
        "-netdev" "${type},id=${id}"
        "-device" "virtio-net-device,netdev=${id},mac=${mac}"
      ]) interfaces) ++
      (builtins.concatMap ({ id
                           , tag ? id
                           , path
                           , writable ? false
                           , security ? (if writable then "mapped-xattr" else "passthrough")
                           }: [
        "-fsdev" "local,id=${id},path=${path},security_model=${security},readonly=${if writable then "off" else "on"}"
        "-device" "virtio-9p-device,fsdev=${id},mount_tag=${tag}"
      ]) shared)
      );
    in
      pkgs.writeScriptBin "run-qemu-${hostName}" ''
        #! ${pkgs.runtimeShell} -e

        ${preStart}

        exec ${qemuCommand}
      '';
}

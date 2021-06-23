{ self, nixpkgs }:

{
  runFirecracker = { system
                   , vcpu ? 1
                   , mem ? 512
                   , nixos
                   , append ? ""
                   , user ? null
                   #, interfaces ? [ { id = "eth0"; type = "user"; } ]
                   #, shared ? []
                   , preStart ? ""
                   }:
    let
      pkgs = nixpkgs.legacyPackages.${system};
      customKernel = pkgs.linuxPackages_custom {
        inherit (pkgs.linuxPackages.kernel) version src;
        configfile = builtins.fetchurl {
          url = "https://mergeboard.com/files/blog/qemu-microvm/defconfig";
          sha256 = "0ml8v19ir3vmhd948n7c0k9gw8br4d70fd02bfxv9yzwl6r1gvd9";
        };
      };
      inherit (nixos.config.networking) hostName;
      rootfs = nixos.config.system.build.toplevel;
      kernel = "${customKernel.kernel.dev}/vmlinux";
      command = nixpkgs.lib.escapeShellArgs ([
        "${pkgs.firectl}/bin/firectl"
        "--firecracker-binary=${pkgs.firecracker}/bin/firecracker"
        "-m" (builtins.toString mem)
        "-c" (builtins.toString vcpu)
        "--kernel=${kernel}"
        "--root-drive=rootfs-${hostName}.ext4"
        "--kernel-opts=console=ttyS0 noapic reboot=k panic=1 pci=off nomodules ro quiet init=${nixos.config.system.build.toplevel}/init ${append}"
      ]
      );
    in
      pkgs.writeScriptBin "run-firecracker" ''
        #! ${pkgs.runtimeShell} -e

        TEMPDIR=$(mktemp -d)
        cp -a --no-preserve=xattr --parents $(${pkgs.nix}/bin/nix-store -qR ${nixos.config.system.build.toplevel}) $TEMPDIR/
        ${pkgs.libguestfs-with-appliance}/bin/virt-make-fs --size=+16M --type=ext4 $TEMPDIR rootfs-${hostName}.ext4
        sudo rm -rf $TEMPDIR

        ${preStart}

        exec ${command}
      '';
}

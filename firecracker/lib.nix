{ self, nixpkgs }:

{
  runFirecracker = { system
                   , vcpu ? 1
                   , mem ? 512
                   , nixosConfig
                   , append ? ""
                   , user ? null
                   #, interfaces ? [ { id = "eth0"; type = "user"; } ]
                   #, shared ? []
                   , preStart ? ""
                   , rootReserve ? "64M"
                   }:
    let
      writablePaths = [
        "/etc"
        "/tmp"
        "/bin"
        "/usr"
        "/nix/var"
        "/home"
        "/root"
        "/var"
      ];
      nixos = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [ (
          { modulesPath, config, ... }:
          {
            imports = [
              (modulesPath + "/profiles/minimal.nix")
            ];

            boot.isContainer = true;
            systemd.services.nix-daemon.enable = false;
            systemd.sockets.nix-daemon.enable = false;
            boot.specialFileSystems =
              builtins.foldl' (result: path: result // {
                "${path}" = {
                  device = path;
                  fsType = "tmpfs";
                };
              }) {} writablePaths;
          }
        ) nixosConfig ];
      };
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
      rootDrive = pkgs.runCommandLocal "rootfs-${hostName}.img" {
        buildInputs = [ pkgs.libguestfs-with-appliance ];
      } ''
        mkdir -p rootfs/{bin,etc,dev,home,nix/var/nix/gcroots,proc,root,run,sys,tmp,usr,var}
        cp -a --no-preserve=xattr --parents \
          $(cat ${pkgs.writeReferencesToFile nixos.config.system.build.toplevel}) \
          rootfs/
        virt-make-fs --size=+${rootReserve} --type=ext4 rootfs $out
      '';
      firectl = pkgs.firectl.overrideAttrs (oa: {
        # allow read-only root-drive
        postPatch = ''
          substituteInPlace options.go \
            --replace "IsReadOnly:   firecracker.Bool(false)," \
            "IsReadOnly:   firecracker.Bool(true),"
        '';
      });
      command = nixpkgs.lib.escapeShellArgs ([
        "${firectl}/bin/firectl"
        "--firecracker-binary=${pkgs.firecracker}/bin/firecracker"
        "-m" (builtins.toString mem)
        "-c" (builtins.toString vcpu)
        "--kernel=${kernel}"
        "--root-drive=${rootDrive}"
        "--kernel-opts=console=ttyS0 noapic reboot=k panic=1 pci=off nomodules ro quiet init=${nixos.config.system.build.toplevel}/init ${append}"
      ]
      );
    in
      pkgs.writeScriptBin "run-firecracker" ''
        #! ${pkgs.runtimeShell} -e

        ${preStart}

        exec ${command}
      '';
}

{ self, nixpkgs }:

{
  runFirecracker = { system
                   , vcpu ? 1
                   , mem ? 512
                   , nixosConfig
                   , append ? ""
                   , user ? null
                   , interfaces ? []
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
      inherit (nixos.config.networking) hostName;
      rootfs = nixos.config.system.build.toplevel;
      rootDrive = self.lib.mkDiskImage {
        inherit system hostName nixos rootReserve;
      };
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
        "--kernel=${self.packages.${system}.virtioKernel.dev}/vmlinux"
        "--root-drive=${rootDrive}"
        "--kernel-opts=console=ttyS0 noapic reboot=k panic=1 pci=off nomodules ro quiet init=${nixos.config.system.build.toplevel}/init ${append}"
      ] ++
      map ({ type ? "tap", id, mac }:
        if type == "tap"
        then "--tap-device=${id}/${mac}"
        else throw "Unsupported interface type ${type} for Firecracker"
      ) interfaces
      );
    in
      pkgs.writeScriptBin "run-firecracker" ''
        #! ${pkgs.runtimeShell} -e

        ${preStart}

        exec ${command}
      '';
}

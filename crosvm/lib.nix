{ self, nixpkgs }:

{
  runCrosvm = { system
              , vcpu ? 1
              , mem ? 512
              , nixosConfig
              , append ? ""
              , user ? null
              , interfaces ? []
              # TODO: , shared ? []
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
      rootDisk = self.lib.mkDiskImage {
        inherit system hostName nixos rootReserve;
      };
      command = nixpkgs.lib.escapeShellArgs ([
        "${pkgs.crosvm}/bin/crosvm" "run"
        "-m" (toString mem)
        "-c" (toString vcpu)
        "-r" rootDisk
        "--shared-dir" "/nix/store/:store"
        "--serial" "type=stdout,console=true,stdin=true"
        "-p" "quiet reboot=k panic=1 nomodules ro init=${nixos.config.system.build.toplevel}/init ${append}"
        "${self.packages.${system}.cloudHypervisorKernel}/bzImage"
      ] ++
      map (_:
        throw "CrosVM networking is not configurable"
      ) interfaces
      );
    in
      pkgs.writeScriptBin "run-crosvm-${hostName}" ''
        #! ${pkgs.runtimeShell} -e

        ${preStart}

        exec ${command}
      '';
}

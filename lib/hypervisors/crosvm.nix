{ self, nixpkgs }:

{
  run = { system
        , vcpu ? 1
        , mem ? 512
        , nixosConfig
        , append ? ""
        , user ? null
        , interfaces ? []
        , volumes ? []
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
            boot.specialFileSystems = (
              builtins.foldl' (result: path: result // {
                "${path}" = {
                  device = path;
                  fsType = "tmpfs";
                };
              }) {} writablePaths
            ) // (
              builtins.foldl' (result: { mountpoint, letter, fsType ? self.lib.defaultFsType, ... }: result // {
                "${mountpoint}" = {
                  device = "/dev/vd${letter}";
                  inherit fsType;
                };
              }) {} (self.lib.withDriveLetters 1 volumes)
            );
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
        "-p" "console=ttyS0 verbose reboot=k panic=1 nomodules ro init=${nixos.config.system.build.toplevel}/init ${append}"
      ] ++
      builtins.concatMap ({ image, ... }:
        [ "--rwdisk" image ]
      ) volumes ++
      map (_:
        throw "CrosVM networking is not configurable"
      ) interfaces ++
      [ "${self.packages.${system}.cloudHypervisorKernel}/bzImage" ]
      );
    in
      pkgs.writeScriptBin "run-crosvm-${hostName}" ''
        #! ${pkgs.runtimeShell} -e

        ${self.lib.createVolumesScript pkgs volumes}
        ${preStart}

        exec ${command}
      '';
}

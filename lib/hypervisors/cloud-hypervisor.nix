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
        "${pkgs.cloud-hypervisor}/bin/cloud-hypervisor"
        "--memory" "size=${toString mem}M,mergeable=on"
        "--cpus" "boot=${toString vcpu}"
        "--rng" "--watchdog"
        "--console" "tty"
        "--kernel" "${self.packages.${system}.cloudHypervisorKernel}/bzImage"
        "--cmdline" "console=hvc0 quiet reboot=t panic=-1 ro root=/dev/vda init=${nixos.config.system.build.toplevel}/init ${append}"
        "--seccomp" "true"
        "--disk" "path=${rootDisk},readonly=on"
      ] ++
      map ({ image, ... }:
        "path=${image}"
      ) volumes ++
      builtins.concatMap ({ type ? "tap", id, mac }:
        if type == "tap"
        then [ "--net" "tap=${id},mac=${mac}" ]
        else throw "Unsupported interface type ${type} for Cloud-Hypervisor"
      ) interfaces
      );
    in
      pkgs.writeScriptBin "run-cloud-hypervisor-${hostName}" ''
        #! ${pkgs.runtimeShell} -e

        ${self.lib.createVolumesScript pkgs volumes}
        ${preStart}

        exec ${command}
      '';
}

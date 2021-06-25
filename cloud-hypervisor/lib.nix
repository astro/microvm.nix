{ self, nixpkgs }:

{
  runCloudHypervisor = { system
                       , vcpu ? 1
                       , mem ? 512
                       , nixosConfig
                       , append ? ""
                       , user ? null
                       # TODO: , interfaces ? []
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
        "${pkgs.cloud-hypervisor}/bin/cloud-hypervisor"
        "--memory" "size=${toString mem}M,mergeable=on"
        "--cpus" "boot=${toString vcpu}"
        "--rng" "--watchdog"
        "--console" "tty"
        "--kernel" "${self.packages.${system}.cloudHypervisorKernel}/bzImage"
        "--disk" "path=${rootDisk},readonly=on"
        "--cmdline" "console=hvc0 quiet reboot=t panic=-1 ro root=/dev/vda init=${nixos.config.system.build.toplevel}/init ${append}"
        "--seccomp" "true"
      ]
      # map ({ type ? "tap", id, mac }:
      #   if type == "tap"
      #   then "--tap-device=${id}/${mac}"
      #   else throw "Unsupported interface type ${type} for Cloud-Hypervisor"
      # ) interfaces
      );
    in
      pkgs.writeScriptBin "run-cloud-hypervisor-${hostName}" ''
        #! ${pkgs.runtimeShell} -e

        ${preStart}

        exec ${command}
      '';
}

{ self, nixpkgs }:

{
  runQemu = { system
            , vcpu ? 1
            , mem ? 512
            , nixosConfig
            , append ? ""
            , user ? null
            , interfaces ? [ { id = "eth0"; type = "user"; mac = "00:23:de:ad:be:ef"; } ]
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
      inherit (nixos.config.networking) hostName;
      pkgs = nixpkgs.legacyPackages.${system};
      arch = builtins.head (builtins.split "-" system);
      rootDisk = self.lib.mkDiskImage {
        inherit system hostName nixos rootReserve;
      };
      qemuCommand = nixpkgs.lib.escapeShellArgs ([
        "${pkgs.qemu}/bin/qemu-system-${arch}"
        "-name" "qemu-${hostName}"
        "-M" "microvm,x-option-roms=off,isa-serial=off,rtc=off"
        "-m" (toString mem)
        "-cpu" "host"
        "-smp" (toString vcpu)
        "-no-acpi" "-enable-kvm"
        "-nodefaults" "-no-user-config"
        "-nographic" "-no-reboot"
        "-device" "virtio-serial-device"
        "-chardev" "stdio,id=virtiocon0"
        "-device" "virtconsole,chardev=virtiocon0"
        "-device" "virtio-rng-device"
        "-drive" "id=root,media=cdrom,file=${rootDisk},if=none" "-device" "virtio-blk-device,drive=root"
        "-kernel" "${self.packages.${system}.virtioKernel}/bzImage"
        "-append" "console=hvc0 acpi=off reboot=t panic=-1 quiet ro root=/dev/vda init=${nixos.config.system.build.toplevel}/init ${append}"
        "-sandbox" "on"
      ] ++
      (if user != null then [ "-user" user ] else []) ++
      builtins.concatMap ({ image, letter, ... }:
        [ "-drive" "id=vd${letter},file=${image},if=none" "-device" "virtio-blk-device,drive=vd${letter}" ]
      ) (self.lib.withDriveLetters 1 volumes) ++
      (builtins.concatMap ({ type, id, mac }: [
        "-netdev" "${type},id=${id}"
        "-device" "virtio-net-device,netdev=${id},mac=${mac}"
      ]) interfaces)
      );
    in
      pkgs.writeScriptBin "run-qemu-${hostName}" ''
        #! ${pkgs.runtimeShell} -e

        ${self.lib.createVolumesScript pkgs volumes}
        ${preStart}

        exec ${qemuCommand}
      '';
}

{ config, lib, pkgs, ... }:

let
  inherit (config.system.boot.loader) kernelFile initrdFile;

  kernelPath =
    "${config.boot.kernelPackages.kernel}/${kernelFile}";
  initrdPath =
    "${config.system.build.initialRamdisk}/${initrdFile}";

in {
  options.microvm = with lib; {
    bootDisk = mkOption {
      type = types.path;
      description = ''
        Generated
      '';
    };
  };

  config = lib.mkIf config.microvm.guest.enable {
    microvm.bootDisk = pkgs.runCommandLocal "microvm-bootdisk.img" {
      nativeBuildInputs = with pkgs; [
        parted
        libguestfs
      ];
      # HACK: Do not evaluate libguestfs-appliance for others than
      #       cloud-hypervisor and on x86_64.
      LIBGUESTFS_PATH = lib.optionalString (config.microvm.hypervisor == "cloud-hypervisor" && pkgs.hostPlatform.isx86_64) pkgs.libguestfs-appliance;
      passthru = {
        kernel = kernelPath;
        initrd = initrdPath;
      };
    } ''
      # kernel + initrd + slack, in sectors
      EFI_SIZE=$(( ( ( $(stat -c %s ${kernelPath}) + $(stat -c %s ${initrdPath}) + 16 * 4096 ) / ( 2048 * 512 ) + 1 ) * 2048 ))

      truncate -s $(( ( $EFI_SIZE + 2048 + 33 ) * 512 )) $out
      echo Creating partition table
      parted --script $out -- \
        mklabel gpt \
        mkpart ESP fat32 2048s $(( $EFI_SIZE + 2048 - 1 ))"s" \
        set 1 boot on

      echo Creating EFI partition
      export HOME=`pwd`
      guestfish --add $out run \: mkfs fat /dev/sda1
      guestfs() {
        guestfish --add $out --mount /dev/sda1:/ $@
      }
      guestfs mkdir /loader
      echo 'default *.conf' > loader.conf
      guestfs copy-in loader.conf /loader/
      guestfs mkdir /loader/entries
      cat > entry.conf <<EOF
      title microvm.nix (${config.system.nixos.label})
      linux /${kernelFile}
      initrd /${initrdFile}
      EOF
      guestfs copy-in entry.conf /loader/entries/
      guestfs copy-in ${kernelPath} /
      guestfs copy-in ${initrdPath} /
    '';
  };
}

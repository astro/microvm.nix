{ nixpkgs-lib }:
rec {
  hypervisors = [
    "qemu"
    "cloud-hypervisor"
    "firestarter"
    "crosvm"
    "kvmtool"
  ];

  defaultFsType = "ext4";

  withDriveLetters = offset: list:
    map ({ fst, snd }:
      fst // {
        letter = snd;
      }
    ) (nixpkgs-lib.zipLists list (
      nixpkgs-lib.drop offset nixpkgs-lib.strings.lowerChars
    ));

  createVolumesScript = pkgs: pkgs.lib.concatMapStringsSep "\n" (
    { image
    , size ? throw "Specify a size for volume ${image} or use autoCreate = false"
    , fsType ? defaultFsType
    , autoCreate ? true
    , ...
    }: nixpkgs-lib.optionalString autoCreate ''
      PATH=$PATH:${with pkgs; lib.makeBinPath [ e2fsprogs ]}

      if [ ! -e ${image} ]; then
        dd if=/dev/zero of=${image} bs=1M count=1 seek=${toString (size - 1)}
        mkfs.${fsType} ${image}
      fi
    '');
}

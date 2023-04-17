{ config, lib }:

let
  interfaceFdOffset = 3;

  macvtapInterfaces =
    lib.imap0 (i: interface:
      interface // {
        fd = interfaceFdOffset + i;
      }) (
        builtins.filter ({ type, ... }:
          type == "macvtap"
        ) config.interfaces
      );

in {
  openMacvtapFds = lib.concatMapStrings ({ id, fd, ... }: ''
    exec ${toString fd}<>/dev/tap$(< /sys/class/net/${id}/ifindex)
  '') macvtapInterfaces;

  macvtapFds = builtins.foldl' (result: { id, fd, ... }:
    result // {
      ${id} = fd;
    }
  ) {
    nextFreeFd = interfaceFdOffset + builtins.length macvtapInterfaces;
  } macvtapInterfaces;
}

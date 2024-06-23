{ config, lib, ... }:
let
  inherit (config.networking) hostName;

in
lib.mkIf config.microvm.guest.enable {
  assertions =
    # check for duplicate volume images
    map (volumes: {
      assertion = builtins.length volumes == 1;
      message = ''
        MicroVM ${hostName}: volume image "${(builtins.head volumes).image}" is used ${toString (builtins.length volumes)} > 1 times.
      '';
    }) (
      builtins.attrValues (
        builtins.groupBy ({ image, ... }: image) config.microvm.volumes
      )
    )
    ++
    # check for duplicate interface ids
    map (interfaces: {
      assertion = builtins.length interfaces == 1;
      message = ''
        MicroVM ${hostName}: interface id "${(builtins.head interfaces).id}" is used ${toString (builtins.length interfaces)} > 1 times.
      '';
    }) (
      builtins.attrValues (
        builtins.groupBy ({ id, ... }: id) config.microvm.interfaces
      )
    )
    ++
    # check for bridge interfaces
    map ({ id, type, bridge, ... }:
      if type == "bridge"
      then {
        assertion = bridge != null;
        message = ''
          MicroVM ${hostName}: interface ${id} is of type "bridge"
          but doesn't have a bridge to attach to defined.
        '';
      }
      else {
        assertion = bridge == null;
        message = ''
          MicroVM ${hostName}: interface ${id} is not of type "bridge"
          and therefore shouldn't have a "bridge" option defined.
        '';
      }
    ) config.microvm.interfaces
    ++
    # check for interface name length
    map ({ id, ... }: {
      assertion = builtins.stringLength id <= 15;
      message = ''
        MicroVM ${hostName}: interface name ${id} is longer than the
        the maximum length of 15 characters on Linux.
      '';
    }) config.microvm.interfaces
    ++
    # check for duplicate share tags
    map (shares: {
      assertion = builtins.length shares == 1;
      message = ''
        MicroVM ${hostName}: share tag "${(builtins.head shares).tag}" is used ${toString (builtins.length shares)} > 1 times.
      '';
    }) (
      builtins.attrValues (
        builtins.groupBy ({ tag, ... }: tag) config.microvm.shares
      )
    )
    ++
    # check for duplicate share sockets
    map (shares: {
      assertion = builtins.length shares == 1;
      message = ''
        MicroVM ${hostName}: share socket "${(builtins.head shares).socket}" is used ${toString (builtins.length shares)} > 1 times.
      '';
    }) (
      builtins.attrValues (
        builtins.groupBy ({ socket, ... }: toString socket) (
          builtins.filter ({ proto, ... }: proto == "virtiofs")
            config.microvm.shares
        )
      )
    )
    ++
    # check for virtiofs shares without socket
    map ({ tag, socket, ... }: {
      assertion = socket != null;
      message = ''
        MicroVM ${hostName}: virtiofs share with tag "${tag}" is missing a `socket` path.
      '';
    }) (
      builtins.filter ({ proto, ... }: proto == "virtiofs")
        config.microvm.shares
    )
    ++
    # blacklist forwardPorts
    [ {
      assertion =
        config.microvm.forwardPorts != [] -> (
          config.microvm.hypervisor == "qemu" &&
          builtins.any ({ type, ... }: type == "user") config.microvm.interfaces
        );
      message = ''
        MicroVM ${hostName}: `config.microvm.forwardPorts` works only with qemu and one network interface with `type = "user"`
      '';
    } ];

  warnings =
    # 32 MB is just an optimistic guess, not based on experience
    lib.optional (config.microvm.mem < 32) ''
      MicroVM ${hostName}: ${toString config.microvm.mem} MB of RAM is uncomfortably narrow.
    '';
}

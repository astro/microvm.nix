{ microvmConfig, hypervisorConfig, lib }:

let
  tapMultiQueue = hypervisorConfig.tapMultiQueue or false;
  # How many queue-pairs per interface?
  queueCount = if tapMultiQueue then microvmConfig.vcpu else 1;

  interfaceFdOffset = 3;

  macvtapInterfaces =
    builtins.concatLists (
      lib.imap0 (interfaceIndex: interface:
        builtins.genList (queueIndex:
          interface // {
            fd = interfaceFdOffset + interfaceIndex * queueCount + queueIndex;
          }) queueCount
      ) (
          builtins.filter ({ type, ... }:
            type == "macvtap"
          ) microvmConfig.interfaces
        )
    );

in {
  openMacvtapFds = ''
    # Open macvtap interface file descriptors
  '' +
  lib.concatMapStrings ({ id, fd, ... }: ''
    exec ${toString fd}<>/dev/tap$(< /sys/class/net/${id}/ifindex)
  '') macvtapInterfaces;

  macvtapFds = builtins.foldl' (result: { id, fd, ... }:
    result // {
      ${id} = (result.${id} or []) ++ [ fd ];
    }
  ) {
    nextFreeFd = interfaceFdOffset + builtins.length macvtapInterfaces;
  } macvtapInterfaces;
}

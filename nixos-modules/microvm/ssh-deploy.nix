{ config, lib, pkgs, ... }:

let
  hostName = config.networking.hostName or "$HOSTNAME";
  inherit (config.system.build) toplevel;
  inherit (config.microvm) declaredRunner;
  inherit (config) nix;

  closureInfo = pkgs.closureInfo {
    rootPaths = [ config.system.build.toplevel ];
  };

  # Don't build these but get the derivation paths for building on a
  # remote host, and for switching via SSH.
  paths = builtins.mapAttrs (_: builtins.unsafeDiscardStringContext) {
    closureInfoOut = closureInfo.outPath;
    closureInfoDrv = closureInfo.drvPath;
    toplevelOut = toplevel.outPath;
    toplevelDrv = toplevel.drvPath;
    nixOut = nix.package.outPath;
    nixDrv = nix.package.drvPath;
    runnerDrv = declaredRunner.drvPath;
  };

  canSwitchViaSsh =
    config.system.switch.enable &&
    # MicroVM must be reachable through SSH
    config.services.openssh.enable &&
    # Is the /nix/store mounted from the host?
    builtins.any ({ source, ... }:
      source == "/nix/store"
    ) config.microvm.shares;

in
{
  # Declarations with documentation
  options.microvm.deploy = {
    installOnHost = lib.mkOption {
      description = ''
        Use this script to deploy the working state of your local
        Flake on a target host that imports
        `microvm.nixosModules.host`:

        ```
        nix run .#nixosConfigurations.${hostName}.config.microvm.deploy.installOnHost root@example.com
        ssh root@example.com systemctl restart microvm@${hostName}
        ```

        - Evaluate this MicroVM to a derivation
        - Copy the derivation to the target host
        - Build the MicroVM runner on the taret host
        - Install/update the MicroVM on the target host

        Can be followed by either:
        - `systemctl restart microvm@${hostName}.service` on the
          target host, or
        - `config.microvm.deploy.sshSwitch`
      '';
      type = lib.types.package;
    };

    sshSwitch = lib.mkOption {
      description = ''
        Instead of restarting a MicroVM for an update, perform it via
        SSH.

        The host's /nix/store must be mounted, and the built
        `config.microvm.declaredRunner` must exist in it. Use
        `microvm.deploy.installOnHost` like this:

        ```
        nix run .#nixosConfigurations.${hostName}.config.microvm.deploy.installOnHost root@example.com
        nix run .#nixosConfigurations.${hostName}.config.microvm.deploy.sshSwitch root@my-microvm.example.com switch
        ```
      '';
      type = with lib.types; nullOr package;
      default = null;
    };

    rebuild = lib.mkOption {
      description = ''
        `config.microvm.deploy.installOnHost` and `.sshSwitch` in one
        script. Akin to what nixos-rebuild does but for a remote
        MicroVM.

        ```
        nix run .#nixosConfigurations.${hostName}.config.microvm.deploy.rebuild root@example.com root@my-microvm.example.com switch
        ```
      '';
      type = with lib.types; nullOr package;
      default = null;
    };
  };

  # Implementations
  config.microvm.deploy = {
    installOnHost = pkgs.writeShellScriptBin "microvm-install-on-host" ''
      set -eou pipefail

      USAGE="Usage: $0 root@<host> [--use-remote-sudo]"

      HOST="$1"
      if [[ -z "$HOST" ]]; then
        echo $USAGE
        exit 1
      fi
      shift
      SSH_CMD="bash"
      if [ $# -gt 0 ]; then
        if [ "$1" == "--use-remote-sudo" ]; then
          SSH_CMD="sudo bash"
          shift
        else
          echo "$USAGE"
          exit 1
        fi
      fi


      echo "Copying derivations to $HOST"
      nix copy --no-check-sigs --to "ssh-ng://$HOST" \
        --derivation \
        "${paths.closureInfoDrv}^out" \
        "${paths.runnerDrv}^out"

      ssh "$HOST" -- $SSH_CMD -e <<__SSH__
      set -eou pipefail

      echo "Initializing MicroVM ${hostName} if necessary"
      mkdir -p /nix/var/nix/gcroots/microvm
      mkdir -p /var/lib/microvms/${hostName}
      cd /var/lib/microvms/${hostName}
      chown microvm:kvm .
      chmod 0755 .
      ln -sfT \$PWD/current /nix/var/nix/gcroots/microvm/${hostName}
      ln -sfT \$PWD/booted /nix/var/nix/gcroots/microvm/booted-${hostName}
      ln -sfT \$PWD/old /nix/var/nix/gcroots/microvm/old-${hostName}

      echo "Building toplevel ${paths.toplevelOut}"
      nix build -L --accept-flake-config --no-link \
        ${with paths; lib.concatMapStringsSep " " (drv: "'${drv}^out'") [
          nixDrv
          closureInfoDrv
          toplevelDrv
        ]}
      echo "Building MicroVM runner for ${hostName}"
      nix build -L --accept-flake-config -o new \
        "${paths.runnerDrv}^out"

      if [[ $(realpath ./current) != $(realpath ./new) ]]; then
        echo "Installing MicroVM ${hostName}"
        rm -f old
        if [ -e current ]; then
          mv current old
        fi
        mv new current

        if [ -e old ]; then
          echo "Success. Diff:"
          nix --extra-experimental-features nix-command \
            store diff-closures ./old ./current \
            || true
        else
          echo "Success."
        fi
      else
        echo "MicroVM ${hostName} is already installed"
      fi
      __SSH__
    '';

    sshSwitch = lib.mkIf canSwitchViaSsh (
      pkgs.writeShellScriptBin "microvm-switch" ''
        set -eou pipefail

        USAGE="Usage: $0 root@<target> [--use-remote-sudo]"

        TARGET="$1"
        if [[ -z "$TARGET" ]]; then
          echo "$USAGE"
          exit 1
        fi
        shift
        SSH_CMD="bash"
        if [ $# -gt 0 ]; then
          if [ "$1" == "--use-remote-sudo" ]; then
            SSH_CMD="sudo bash"
            shift
          else
            echo "$USAGE"
            exit 1
          fi
        fi

        ssh "$TARGET" $SSH_CMD -e <<__SSH__
        set -eou pipefail

        hostname=\$(cat /etc/hostname)
        if [[ "\$hostname" != "${hostName}" ]]; then
          echo "Attempting to deploy NixOS ${hostName} on host \$hostname"
          exit 1
        fi

        # refresh nix db which is required for nix-env -p ... --set
        echo "Refreshing Nix database"
        ${paths.nixOut}/bin/nix-store --load-db < ${paths.closureInfoOut}/registration
        ${paths.nixOut}/bin/nix-env -p /nix/var/nix/profiles/system --set ${paths.toplevelOut}

        ${paths.toplevelOut}/bin/switch-to-configuration "''${@:-switch}"
        __SSH__
      ''
    );

    rebuild = with config.microvm.deploy; pkgs.writeShellScriptBin "microvm-rebuild" ''
      set -eou pipefail

      HOST="$1"
      shift
      TARGET="$1"
      shift
      OPTS="$@"
      if [ $# -gt 0 ]; then
        if [ "$1" == "--use-remote-sudo" ]; then
          OPTS="$1"
          shift
        fi
      fi
      if [[ -z "$HOST" || -z "$TARGET" || $# -gt 0 ]]; then
        echo "Usage: $0 root@<host> root@<target> [--use-remote-sudo] switch"
        exit 1
      fi

      ${lib.getExe installOnHost} "$HOST" $OPTS
      ${if canSwitchViaSsh
        then ''${lib.getExe sshSwitch} "$TARGET" $OPTS''
        else ''ssh "$HOST" -- systemctl restart "microvm@${hostName}.service"''
       }
    '';
  };
}

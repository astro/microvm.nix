{ pkgs }:

with pkgs;

writeScriptBin "microvm" ''
  #! ${pkgs.runtimeShell} -e

  PATH=$PATH:${lib.makeBinPath [ git nixFlakes ]}
  STATE_DIR=/var/lib/microvms
  ACTION=help

  OPTERR=1
  while getopts ":c:u:r:s:" arg; do
    case $arg in
      c)
        ACTION=create
        NAME=$OPTARG
        ;;
      u)
        ACTION=update
        NAME=$OPTARG
        ;;
      r)
        ACTION=run
        NAME=$OPTARG
        ;;
      s)
        ACTION=shutdown
        NAME=$OPTARG
        ;;

      ?)
        ACTION=help
        ;;
    esac
  done
  DIR=$STATE_DIR/$NAME

  build() {
    TMP=$(mktemp -d)
    nix build -o $TMP/run $1#microvm.runScript
    nix build -o $TMP/shutdown $1#microvm.shutdownScript
    mv $TMP/* $1/
    rmdir $TMP
  }

  case $ACTION in
    help)
      echo Help:
      cat << EOF
Usage: $0 <action> [flags...]

Actions:
          -c <name>  Create a MicroVM
          -u <name>  Rebuild a MicroVM
          -r <name>  Run a MicroVM in foreground
          -s <name>  Shutdown a running MicroVM
EOF
      ;;
    create)
      TEMP=$(mktemp -d)
      pushd $TEMP

      git init
      cat > flake.nix << EOF
{
  inputs.microvm.url = "github:astro/microvm.nix";

  outputs = { self, microvm }: {
    defaultApp.${system} = self.apps.${system}.run;
    apps.${system} = {
      run = {
        type = "app";
        program = toString self.packages.${system}.microvm.runScript;
      };
      shutdown = {
        type = "app";
        program = toString self.packages.${system}.microvm.shutdownScript;
      };
    };

    packages.${system}.microvm = microvm.lib.makeMicrovm {
      system = "${system}";
      hypervisor = "cloud-hypervisor";
      nixosConfig = self.nixosConfigurations.$NAME;
      socket = "$DIR/socket";

      volumes = [ {
        mountpoint = "/var";
        image = "$DIR/var.img";
        size = 256;
      } ];
      # vcpu = 1;
      # mem = 512;
      # # ...
    };

    nixosConfigurations.$NAME = { ... }: {
      networking.hostName = "$NAME";
      users.users.root.password = "";
    };
  };
}
EOF
      git add flake.nix
      nix flake update . --override-flake microvm ${./..}
      git add flake.lock
      build .

      popd
      if [ -e $DIR ]; then
        echo $DIR already exists.
        exit 1
      fi
      mv $TEMP $DIR
      chown :kvm -R $DIR
      chmod -R a+rX -R $DIR
      chmod g+w $DIR
      ;;

    update)
      build $DIR
      ;;

    run)
      nix run git+file://$DIR#run
      ;;

    shutdown)
      nix run git+file://$DIR#shutdown
      ;;
  esac
''

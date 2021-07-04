{ pkgs }:

with pkgs;

writeScriptBin "microvm" ''
  #! ${pkgs.runtimeShell}
  set -e

  PATH=$PATH:${lib.makeBinPath [ git nixFlakes jq ]}
  STATE_DIR=/var/lib/microvms
  ACTION=help
  FLAKE=git+file:///etc/nixos

  OPTERR=1
  while getopts ":c:f:u:r:s:" arg; do
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

      f)
        FLAKE=$OPTARG
        ;;

      ?)
        ACTION=help
        ;;
    esac
  done
  DIR=$STATE_DIR/$NAME

  build() {
    NAME=$1
    FLAKE=$(cat flake)

    echo "Building $FLAKE#$NAME"

    TMP=$(mktemp -d)
    nix build -o $TMP/output $FLAKE#$NAME
    OUTPUT=$(readlink $TMP/output)
    rm $TMP/output
    rmdir $TMP
    ln -s $OUTPUT/bin/microvm-run .
    ln -s $OUTPUT/bin/microvm-shutdown .
  }

  case $ACTION in
    help)
      echo Help:
      cat << EOF
Usage: $0 <action>

Actions:
          -c <name>  Create a MicroVM
          -u <name>  Rebuild a MicroVM
          -r <name>  Run a MicroVM in foreground
          -s <name>  Shutdown a running MicroVM
          -l         List MicroVMs
EOF
      ;;
    create)
      TEMP=$(mktemp -d)
      pushd $TEMP
      echo -n "$FLAKE" > flake
      build $NAME

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
      pushd $DIR
      build $NAME

      # TODO: echo No update required for $NAME
      ;;

    run)
      exec $DIR/run
      ;;

    shutdown)
      exec nix run $DIR/shutdown
      ;;
  esac
''

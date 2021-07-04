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
  while getopts ":c:f:u:r:s:l" arg; do
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
      l)
        ACTION=list
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
    nix build -o $TMP/output $FLAKE#$NAME >/dev/null
    OUTPUT=$(readlink $TMP/output)
    rm $TMP/output
    rmdir $TMP
    ln -sf $OUTPUT/bin/microvm-run .
    ln -sf $OUTPUT/bin/microvm-shutdown .
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

Flags:
          -f <flake> Create using another flake than `git+file:///etc/nixos`
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
      BUILT=$(dirname $(dirname $(readlink microvm-run)))
      if [ -L booted ]; then
        BOOTED=$(readlink booted)
        if [ $BUILT = $BOOTED ]; then
          echo No reboot of MicroVM $NAME required
        else
          echo You need to reboot MicroVM $NAME for the new profile
        fi
      fi
      ;;

    run)
      exec $DIR/run
      ;;

    shutdown)
      exec nix run $DIR/shutdown
      ;;

    list)
      LIST=$(mktemp)
      for DIR in $STATE_DIR/* ; do
        NAME=$(basename $DIR)
        if [ -d $DIR ] ; then
          CURRENT=$(dirname $(dirname $(readlink $DIR/microvm-run)))

          TEMP=$(mktemp -d)
          pushd $TEMP
          cp $DIR/flake .
          build $NAME
          BUILT=$(dirname $(dirname $(readlink microvm-run)))
          echo -n "$NAME: "
          if [ $CURRENT != $BUILT ]; then
            echo outdated, update required
          elif [ -L $DIR/booted ]; then
            BOOTED=$(readlink $DIR/booted)
            if [ $BUILT = $BOOTED ]; then
              echo current, running
            else
              echo built, restart required
            fi
          else
            echo "built, not booted"
          fi

          popd
          rm -rf $TEMP
        fi
      done >$LIST
      cat $LIST
      rm $LIST
      ;;
  esac
''

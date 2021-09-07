{ pkgs }:

with pkgs;

writeScriptBin "microvm" ''
  #! ${pkgs.runtimeShell}
  set -e

  PATH=$PATH:${lib.makeBinPath [ git nixFlakes jq ]}
  STATE_DIR=/var/lib/microvms
  ACTION=help
  FLAKE=git+file:///etc/nixos
  RESTART=n

  OPTERR=1
  while getopts ":c:f:u:Rr:s:l" arg; do
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
      l)
        ACTION=list
        ;;

      f)
        FLAKE=$OPTARG
        ;;

      R)
        RESTART=y
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

    TMP=$(mktemp -d)
    nix build -o $TMP/output $FLAKE#$NAME >/dev/null
    OUTPUT=$(readlink $TMP/output)
    rm $TMP/output
    rmdir $TMP
    ln -sf $OUTPUT/bin/microvm-run .
    ln -sf $OUTPUT/bin/microvm-shutdown .
    cp $OUTPUT/share/microvm/tap-interfaces .
    [ -e $OUTPUT/share/microvm/virtiofs ] && cp -r $OUTPUT/share/microvm/virtiofs .
    chmod -R u+rwX .
  }

  case $ACTION in
    help)
      echo Help:
      cat << EOF
Usage: $0 <action> [flags]

Actions:
          -c <name>  Create a MicroVM
          -u <name>  Rebuild (update) a MicroVM
          -r <name>  Run a MicroVM in foreground
          -l         List MicroVMs

Flags:
          -f <flake> Create using another flake than $FLAKE
          -R         Restart after update
EOF
      ;;
    create)
      TEMP=$(mktemp -d)
      pushd $TEMP > /dev/null
      echo -n "$FLAKE" > flake
      build $NAME

      popd > /dev/null
      if [ -e $DIR ]; then
        echo $DIR already exists.
        exit 1
      fi
      mv $TEMP $DIR
      chown :kvm -R $DIR
      chmod -R a+rX $DIR
      chmod g+w $DIR

      mkdir -p /nix/var/nix/gcroots/microvm
      rm -f /nix/var/nix/gcroots/microvm/$NAME
      ln -s $DIR/microvm-run /nix/var/nix/gcroots/microvm/$NAME
      ;;

    update)
      pushd $DIR > /dev/null
      build $NAME

      BUILT=$(dirname $(dirname $(readlink microvm-run)))
      if [ -L booted ]; then
        BOOTED=$(readlink booted)
        if [ $BUILT = $BOOTED ]; then
          echo No reboot of MicroVM $NAME required
        else
          if [ $RESTART = y ]; then
            echo Rebooting MicroVM $NAME
            systemctl restart microvm@$NAME.service
          else
            echo Reboot MicroVM $NAME for the new profile: systemctl restart microvm@$NAME.service
          fi
        fi
      fi
      ;;

    run)
      exec $DIR/microvm-run
      ;;

    list)
      for DIR in $STATE_DIR/* ; do
        NAME=$(basename $DIR)
        if [ -d $DIR ] ; then
          CURRENT=$(dirname $(dirname $(readlink $DIR/microvm-run)))
          FLAKE=$(cat $DIR/flake)
          NEW=$(nix eval --raw $FLAKE#$NAME)

          echo -n "$NAME: "
          if [ $CURRENT != $NEW ]; then
            echo outdated, update required
          elif [ -L $DIR/booted ]; then
            BOOTED=$(readlink $DIR/booted)
            if [ $NEW = $BOOTED ]; then
              echo current, running
            else
              echo built, reboot required: systemctl restart microvm@$NAME.service
            fi
          else
            echo "built, not booted: systemctl start microvm@$NAME.service"
          fi
        fi
      done
      ;;
  esac
''

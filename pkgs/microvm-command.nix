{ pkgs }:

with pkgs;

let
  colors = {
    normal = "\\033[0m";
    red = "\\033[0;31m";
    green = "\\033[0;32m";
    boldRed = "\\033[1;31m";
    boldYellow = "\\033[1;33m";
    boldGreen = "\\033[1;32m";
    boldCyan = "\\033[1;36m";
  };
  colored = color: text: "${colors.${color}}${text}${colors.normal}";
in
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
          NEW=$(nix eval --raw $FLAKE#$NAME 2>/dev/null)

          if systemctl is-active -q microvm@$NAME ; then
            echo -n -e "${colors.boldGreen}"
          elif [ -e "$DIR/booted" ]; then
            echo -n -e "${colors.boldYellow}"
          else
            echo -n -e "${colors.boldRed}"
          fi
          echo -n -e "$NAME${colors.normal}: "
          if [ "$CURRENT" != "$NEW" ] ; then
            echo -e "${colored "red" "outdated"}, rebuild and reboot: ${colored "boldCyan" "microvm -Ru $NAME"}"
          elif [ -L "$DIR/booted" ]; then
            BOOTED=$(readlink "$DIR/booted")
            if [ "$NEW" = "$BOOTED" ]; then
              echo -e "${colored "green" "current"}"
            else
              echo -e "${colored "red" "stale"}, reboot: ${colored "boldCyan" "systemctl restart microvm@$NAME.service"}"
            fi
          else
            echo -e "${colored "green" "current"}, not booted: ${colored "boldCyan" "systemctl start microvm@$NAME.service"}}"
          fi
        fi
      done
      ;;
  esac
''

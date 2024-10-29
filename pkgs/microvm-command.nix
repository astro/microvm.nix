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
writeShellScriptBin "microvm" ''
  set -e

  PATH=${lib.makeBinPath [
    git jq nix
  ]}:$PATH
  STATE_DIR=/var/lib/microvms
  ACTION=help
  FLAKE=git+file:///etc/nixos
  RESTART=n

  OPTERR=1
  while getopts ":c:C:f:uRr:s:l" arg; do
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
  # consume all $@ that were processed by getopts
  shift $((OPTIND -1))
  DIR=$STATE_DIR/$NAME

  build() {
    NAME=$1

    if [ -e toplevel ]; then
      echo -e "${colored "red" "This MicroVM is managed fully declaratively and cannot be updated manually!"}"
      return 1
    fi

    FLAKE=$(cat flake)

    nix build -o current "$FLAKE"#nixosConfigurations."$NAME".config.microvm.declaredRunner >/dev/null
    chmod -R u+rwX .
  }

  case $ACTION in
    help)
      echo Help:
      cat << EOF
  Usage: $0 <action> [flags]

  Actions:
          -c <name>   Create a MicroVM
          -u <names>  Rebuild (update) MicroVMs
          -r <name>   Run a MicroVM in foreground
          -l          List MicroVMs

  Flags:
          -f <flake>  Create using another flake than $FLAKE
          -R          Restart after update
  EOF
      ;;
    create)
      TEMP=$(mktemp -d)
      pushd "$TEMP" > /dev/null
      echo -n "$FLAKE" > flake
      build "$NAME"

      popd > /dev/null
      if [ -e "$DIR" ]; then
        echo "$DIR already exists."
        exit 1
      fi
      mv "$TEMP" "$DIR"
      chown :kvm -R "$DIR"
      chmod -R a+rX "$DIR"
      chmod g+w "$DIR"

      mkdir -p /nix/var/nix/gcroots/microvm
      rm -f "/nix/var/nix/gcroots/microvm/$NAME"
      ln -s "$DIR/current" "/nix/var/nix/gcroots/microvm/$NAME"
      rm -f "/nix/var/nix/gcroots/microvm/booted-$NAME"
      ln -s "$DIR/booted" "/nix/var/nix/gcroots/microvm/booted-$NAME"

      echo -e "${colored "green" "Created MicroVM $NAME."} Start with: ${colored "boldCyan" "systemctl start microvm@$NAME.service"}"
      ;;

    update)
      for NAME in "$@" ; do
        DIR="$STATE_DIR/$NAME"
        pushd "$DIR" > /dev/null
        OLD=""
        [ -L current ] && OLD=$(readlink current)
        build "$NAME"

        BUILT=$(readlink current)
        [ -n "$OLD" ] && nix store diff-closures "$OLD" "$BUILT"

        if [ -L booted ]; then
          BOOTED=$(readlink booted)
          if [ "$BUILT" = "$BOOTED" ]; then
            echo "No reboot of MicroVM $NAME required."
          else
            if [ $RESTART = y ]; then
              echo "Rebooting MicroVM $NAME"
              systemctl restart "microvm@$NAME.service"
            else
              echo "Reboot MicroVM $NAME for the new profile: systemctl restart microvm@$NAME.service"
            fi
          fi
        elif [ "$RESTART" = y ]; then
          echo "Booting MicroVM $NAME"
          systemctl restart "microvm@$NAME.service"
        fi
      done
      ;;

    run)
      cd "$DIR"
      exec ./current/bin/microvm-run
      ;;

    list)
      for DIR in "$STATE_DIR"/* ; do
        NAME=$(basename "$DIR")
        if [ -d "$DIR" ] && [ -L "$DIR/current" ] ; then
          CURRENT_SYSTEM=$(readlink "$DIR/current/share/microvm/system")
          CURRENT=''${CURRENT_SYSTEM#*-}

          if [ -e "$DIR/toplevel" ]; then
            # Should always equal current system
            NEW_SYSTEM=$(readlink "$DIR/toplevel")
          else
            FLAKE=$(cat "$DIR/flake")
            NEW_SYSTEM=$(nix --option narinfo-cache-negative-ttl 10 eval --raw "$FLAKE#nixosConfigurations.$NAME.config.system.build.toplevel" || echo error)
          fi
          NEW=''${NEW_SYSTEM#*-}

          if systemctl is-active -q "microvm@$NAME" ; then
            echo -n -e "${colors.boldGreen}"
          elif [ -e "$DIR/booted" ]; then
            echo -n -e "${colors.boldYellow}"
          else
            echo -n -e "${colors.boldRed}"
          fi
          echo -n -e "''${NAME}${colors.normal}: "
          if [ "$CURRENT_SYSTEM" != "$NEW_SYSTEM" ] ; then
            echo -e "${colored "red" "outdated"}(${colored "red" "$CURRENT"}), rebuild(${colored "green" "$NEW"}) and reboot: ${colored "boldCyan" "microvm -Ru $NAME"}"
          elif [ -L "$DIR/booted" ]; then
            BOOTED_SYSTEM=$(readlink "$DIR/booted/share/microvm/system")
            BOOTED=''${BOOTED_SYSTEM#*-}
            if [ "$NEW_SYSTEM" = "$BOOTED_SYSTEM" ]; then
              echo -e "${colored "green" "current"}(${colored "green" "$BOOTED"})"
            else
              echo -e "${colored "red" "stale"}(${colored "green" "$BOOTED"}), reboot(${colored "green" "$NEW"}): ${colored "boldCyan" "systemctl restart microvm@$NAME.service"}"
            fi
          else
            echo -e "${colored "green" "current"}(${colored "green" "$CURRENT"}), not booted: ${colored "boldCyan" "systemctl start microvm@$NAME.service"}"
          fi
        fi
      done
      ;;
  esac
''

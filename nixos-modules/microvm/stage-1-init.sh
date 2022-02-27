#! @shell@

##
# A stripped-down copy of nixos/modules/system/boot/stage-1-init.sh adapted for MicroVMs
##

targetRoot=/mnt-root
console=tty1

info() {
    echo "$@"
}

extraUtils="@extraUtils@"
export LD_LIBRARY_PATH=@extraUtils@/lib
export PATH=@extraUtils@/bin

fail() {
    if [ -n "$panicOnFail" ]; then exit 1; fi

    # If starting stage 2 failed, allow the user to repair the problem
    # in an interactive shell.
    cat <<EOF

An error occurred in stage 1 of the boot process, which must mount the
root filesystem on \`$targetRoot' and then start stage 2.  Press one
of the following keys:

EOF
    if [ -n "$allowShell" ]; then cat <<EOF
  i) to launch an interactive shell
  f) to start an interactive shell having pid 1 (needed if you want to
     start stage 2's init manually)
EOF
    fi
    cat <<EOF
  r) to reboot immediately
  *) to ignore the error and continue
EOF

    read -n 1 reply

    if [ -n "$allowShell" -a "$reply" = f ]; then
        exec setsid @shell@ -c "exec @shell@ < /dev/$console >/dev/$console 2>/dev/$console"
    elif [ -n "$allowShell" -a "$reply" = i ]; then
        echo "Starting interactive shell..."
        setsid @shell@ -c "exec @shell@ < /dev/$console >/dev/$console 2>/dev/$console" || fail
    elif [ "$reply" = r ]; then
        echo "Rebooting..."
        reboot -f
    else
        info "Continuing..."
    fi
}

trap 'fail' 0


# Print a greeting.
info
info "[1;32m<<< MicroVM.nix Stage 1 >>>[0m"
info

# Make several required directories.
mount -n -t tmpfs -o mode=755,size=50% tmpfs /etc
touch /etc/fstab # to shut up mount
ln -s /proc/mounts /etc/mtab # to shut up mke2fs

# Mount special file systems.
specialMount() {
  local device="$1"
  local mountPoint="$2"
  local options="$3"
  local fsType="$4"

  mkdir -m 0755 -p "$mountPoint"
  mount -n -t "$fsType" -o "$options" "$device" "$mountPoint"
}
source @earlyMountScript@

# Process the kernel command line.
export stage2Init=/init
for o in $(cat /proc/cmdline); do
    case $o in
        console=*)
            set -- $(IFS==; echo $o)
            params=$2
            set -- $(IFS=,; echo $params)
            console=$1
            ;;
        stage2init=*)
            set -- $(IFS==; echo $o)
            stage2Init=$2
            ;;
        boot.trace|debugtrace)
            # Show each command.
            set -x
            ;;
        boot.shell_on_fail)
            allowShell=1
            ;;
        boot.debug1|debug1) # stop right away
            allowShell=1
            fail
            ;;
        boot.debug1devices) # stop after loading modules and creating device nodes
            allowShell=1
            debug1devices=1
            ;;
        boot.debug1mounts) # stop after mounting file systems
            allowShell=1
            debug1mounts=1
            ;;
        boot.panic_on_fail|stage1panic=1)
            panicOnFail=1
            ;;
        root=*)
            # If a root device is specified on the kernel command
            # line, make it available through the symlink /dev/root.
            # Recognise LABEL= and UUID= to support UNetbootin.
            set -- $(IFS==; echo $o)
            if [ $2 = "LABEL" ]; then
                root="/dev/disk/by-label/$3"
            elif [ $2 = "UUID" ]; then
                root="/dev/disk/by-uuid/$3"
            else
                root=$2
            fi
            ln -s "$root" /dev/root
            ;;
        copytoram)
            copytoram=1
            ;;
        findiso=*)
            # if an iso name is supplied, try to find the device where
            # the iso resides on
            set -- $(IFS==; echo $o)
            isoPath=$2
            ;;
    esac
done

# Create device nodes in /dev.
ln -sfn /proc/self/fd /dev/fd
ln -sfn /proc/self/fd/0 /dev/stdin
ln -sfn /proc/self/fd/1 /dev/stdout
ln -sfn /proc/self/fd/2 /dev/stderr


if test -n "$debug1devices"; then fail; fi


# Check the specified file system, if appropriate.
checkFS() {
    local device="$1"
    local fsType="$2"

    # Only check block devices.
    if [ ! -b "$device" ]; then return 0; fi

    # Don't check ROM filesystems.
    if [ "$fsType" = iso9660 -o "$fsType" = udf ]; then return 0; fi

    # Don't check resilient COWs as they validate the fs structures at mount time
    if [ "$fsType" = btrfs -o "$fsType" = zfs -o "$fsType" = bcachefs ]; then return 0; fi

    # Skip fsck for apfs as the fsck utility does not support repairing the filesystem (no -a option)
    if [ "$fsType" = apfs ]; then return 0; fi

    # Skip fsck for nilfs2 - not needed by design and no fsck tool for this filesystem.
    if [ "$fsType" = nilfs2 ]; then return 0; fi

    # Skip fsck for inherently readonly filesystems.
    if [ "$fsType" = squashfs ]; then return 0; fi

    # If we couldn't figure out the FS type, then skip fsck.
    if [ "$fsType" = auto ]; then
        echo 'cannot check filesystem with type "auto"!'
        return 0
    fi

    # Device might be already mounted manually
    # e.g. NBD-device or the host filesystem of the file which contains encrypted root fs
    if mount | grep -q "^$device on "; then
        echo "skip checking already mounted $device"
        return 0
    fi

    # Optionally, skip fsck on journaling filesystems.  This option is
    # a hack - it's mostly because e2fsck on ext3 takes much longer to
    # recover the journal than the ext3 implementation in the kernel
    # does (minutes versus seconds).
    if test -z "@checkJournalingFS@" -a \
        \( "$fsType" = ext3 -o "$fsType" = ext4 -o "$fsType" = reiserfs \
        -o "$fsType" = xfs -o "$fsType" = jfs -o "$fsType" = f2fs \)
    then
        return 0
    fi

    echo "checking $device..."

    fsckFlags=
    if test "$fsType" != "btrfs"; then
        fsckFlags="-V -a"
    fi
    fsck $fsckFlags "$device"
    fsckResult=$?

    if test $(($fsckResult | 2)) = $fsckResult; then
        echo "fsck finished, rebooting..."
        sleep 3
        reboot -f
    fi

    if test $(($fsckResult | 4)) = $fsckResult; then
        echo "$device has unrepaired errors, please fix them manually."
        fail
    fi

    if test $fsckResult -ge 8; then
        echo "fsck on $device failed."
        fail
    fi

    return 0
}


# Function for mounting a file system.
mountFS() {
    local device="$1"
    local mountPoint="$2"
    local options="$3"
    local fsType="$4"

    if [ "$fsType" = auto ]; then
        fsType=$(blkid -o value -s TYPE "$device")
        if [ -z "$fsType" ]; then fsType=auto; fi
    fi

    # Filter out x- options, which busybox doesn't do yet.
    local optionsFiltered="$(IFS=,; for i in $options; do if [ "${i:0:2}" != "x-" ]; then echo -n $i,; fi; done)"
    # Prefix (lower|upper|work)dir with /mnt-root (overlayfs)
    local optionsPrefixed="$( echo "$optionsFiltered" | sed -E 's#\<(lowerdir|upperdir|workdir)=#\1=/mnt-root#g' )"

    echo "$device /mnt-root$mountPoint $fsType $optionsPrefixed" >> /etc/fstab

    checkFS "$device" "$fsType"

    # Create backing directories for overlayfs
    if [ "$fsType" = overlay ]; then
        for i in upper work; do
             dir="$( echo "$optionsPrefixed" | grep -o "${i}dir=[^,]*" )"
             mkdir -m 0700 -p "${dir##*=}"
        done
    fi

    info "mounting $device on $mountPoint..."

    mkdir -p "/mnt-root$mountPoint"

    # For ZFS and CIFS mounts, retry a few times before giving up.
    # We do this for ZFS as a workaround for issue NixOS/nixpkgs#25383.
    local n=0
    while true; do
        mount "/mnt-root$mountPoint" && break
        if [ \( "$fsType" != cifs -a "$fsType" != zfs \) -o "$n" -ge 10 ]; then fail; break; fi
        echo "retrying..."
        sleep 1
        n=$((n + 1))
    done

    true
}


exec 3< @fsInfo@


while read -u 3 mountPoint; do
    read -u 3 device
    read -u 3 fsType
    read -u 3 options

    # !!! Really quick hack to support bind mounts, i.e., where the
    # "device" should be taken relative to /mnt-root, not /.  Assume
    # that every device that starts with / but doesn't start with /dev
    # is a bind mount.
    pseudoDevice=
    case $device in
        /dev/*)
            ;;
        //*)
            # Don't touch SMB/CIFS paths.
            pseudoDevice=1
            ;;
        /*)
            device=/mnt-root$device
            ;;
        *)
            # Not an absolute path; assume that it's a pseudo-device
            # like an NFS path (e.g. "server:/path").
            pseudoDevice=1
            ;;
    esac

    mountFS "$device" "$mountPoint" "$options" "$fsType"
done

exec 3>&-

mkdir -m 0755 -p $targetRoot/proc $targetRoot/sys $targetRoot/dev $targetRoot/run $targetRoot/tmp

@postMountCommands@

# Kill any remaining processes, just to be sure we're not taking any
# with us into stage 2. But keep storage daemons like unionfs-fuse.
#
# Storage daemons are distinguished by an @ in front of their command line:
# https://www.freedesktop.org/wiki/Software/systemd/RootStorageDaemons/
for pid in $(pgrep -v -f '^@'); do
    # Make sure we don't kill kernel processes, see #15226 and:
    # http://stackoverflow.com/questions/12213445/identifying-kernel-threads
    readlink "/proc/$pid/exe" &> /dev/null || continue
    # Try to avoid killing ourselves.
    [ $pid -eq $$ ] && continue
    kill -9 "$pid"
done

if test -n "$debug1mounts"; then fail; fi


# Restore /proc/sys/kernel/modprobe to its original value.
echo /sbin/modprobe > /proc/sys/kernel/modprobe

# Start stage 2.  `switch_root' deletes all files in the ramfs on the
# current root.  The path has to be valid in the chroot not outside.
if [ ! -e "$targetRoot/$stage2Init" ]; then
    stage2Check=${stage2Init}
    while [ "$stage2Check" != "${stage2Check%/*}" ] && [ ! -L "$targetRoot/$stage2Check" ]; do
        stage2Check=${stage2Check%/*}
    done
    if [ ! -L "$targetRoot/$stage2Check" ]; then
        echo "stage 2 init script ($targetRoot/$stage2Init) not found"
        fail
    fi
fi

mount --move /proc $targetRoot/proc
mount --move /sys $targetRoot/sys
mount --move /dev $targetRoot/dev
mount --move /run $targetRoot/run
umount /etc

targetBin=$(dirname $stage2Init)/sw/bin
cd $targetRoot
mkdir mnt
pivot_root . mnt
exec $targetBin/env -i $targetBin/sh -c "$targetBin/umount /mnt; exec $stage2Init"

fail # should never be reached

#!/bin/sh
#
# build-rssh-chroot.sh - build complete rssh chroot cage
#

progname=`basename $0`

Usage() {
    echo "$progname [ CHROOTDIR ]"
    exit 1
}

if [ $# -gt 1 ]; then
    Usage
elif [ -n "$1" ]; then
    CHROOTDIR=$1       
else
    CHROOTDIR=/usr/local/chroot/
fi

# Sanitize CHROOTDIR to prevent confusion
CHROOTDIR="`readlink --canonicalize "$CHROOTDIR"`"
case $CHROOTDIR in
    '')
	echo "Error: blank CHROOTDIR" >&2
	exit 1
	;;
    /|*:*|*' '*)
	echo "Error: unallowed CHROOTDIR \"$CHROOTDIR\"" >&2
	exit 1
	;;
    *:*)
esac

if [ ! -d $CHROOTDIR ]; then
    echo "Error: non-existent \"$CHROOTDIR\"" >&2
    exit 1
fi

echo "progname: building chrootdir: $CHROOTDIR"

#findlibs() {
#    for bin in $@; do
#	echo Checking libraries for $bin >&2
#	if [ ! -x $1 -o ! -f $1 ]; then
#	    echo Skipping non-executable $1 >&2
#	else
#	    # Alternative listings for actual libraries
#	    ldd $1 | awk '{print $1}' | grep ^/ | \
#	    ldd $1 | awk '{print $3}' | grep ^/
#	fi
#    done
#}

rsynctarget() {
    target=$1
    if [ $# -ne 1 ]; then
	echo "Error: Bad argument to rsynctarget, exiting" >&2
	exit 1
    fi
    
    if [ ! -e "$target" ]; then
	echo "Warning: rsynctarget skipping nonexistent $target" >&2
	return 1
    fi
	
    echo "    rsynctarget: rsyncing $target"
    if [ -L "$target" ]; then
	echo "Replicating symlink: $target"
	rsync -a -H -R "$target" $CHROOTDIR
	link="`readlink "$target"`"
	case "$link" in
	    /*)
		rsynctarget $link
		;;
	    *)
		link="`dirname "$target"`/$link"
		export link
		echo  "    link with target dirname: $link"
		rsynctarget "$link"
		;;
	esac
    elif [ -d "$target" ]; then
	# Use readlink to clean out symlinks
	target="`readlink --canonicalize $target`"
	case "$target" in
	    */)
		# Replicate contents of directory
		echo "Replicating contents: $target"
		rsync -a -H -R "$target" $CHROOTDIR
		return $?
		;;
	    *)
		# Replicate directory only
		echo "Replicating directory: $target"
		rsync -a -H -R --exclude=$target/* "$target" $CHROOTDIR
		return $?
		;;
	esac
    else
	# Use readlink to clean out symlinks
	target="`readlink --canonicalize $target`"
	#echo "Replicating file: $target"
	rsync -a -H -R "$target" "$CHROOTDIR" || return $?
	return $?
    fi
}

echo "$progname: Replicating bare directories"
LIBDIRS=''
LIBDIRS="$LIBDIRS /dev"
LIBDIRS="$LIBDIRS /etc"
LIBDIRS="$LIBDIRS /usr"

# All librari directories
LIBDIRS="$LIBDIRS /usr/bin"
LIBDIRS="$LIBDIRS /usr/lib"
LIBDIRS="$LIBDIRS /usr/lib64"
LIBDIRS="$LIBDIRS /usr/sbin"

# These are being replaced with symlinks in Fedora and RHEL 7
LIBDIRS="$LIBDIRS /bin"
LIBDIRS="$LIBDIRS /lib"
LIBDIRS="$LIBDIRS /lib64"
LIBDIRS="$LIBDIRS /sbin"


for libdir in $LIBDIRS; do
    rsynctarget "$libdir"
done



DEVICES="$DEVICES /dev/null"
# Useful for enabling syslog or rsyslog
DEVICES="$DEVICES /dev/log"
# Potentially useful for ssh or scp as actual user in chroot cage
DEVICES="$DEVICES /dev/urandom"
DEVICES="$DEVICES /dev/random"
DEVICES="$DEVICES /dev/zero"
for device in $DEVICES; do
    rsynctarget "$device"
done



echo "$progname: Replicating files and populated directories"
FILES=''
FILES="$FILES /etc/ld.so.cache"
FILES="$FILES /etc/ld.so.cache.d/"
FILES="$FILES /etc/ld.so.conf"
FILES="$FILES /etc/nsswitch.conf"
FILES="$FILES /etc/hosts"
FILES="$FILES /etc/resolv.conf"

for file in $FILES; do
    rsynctarget "$file"
done

echo "$progname: Replicating files and populated directories"
# Works around /bin symlinks in Fedora and RHEL 7
FILES=''
FILES="$FILES /bin/bash"
FILES="$FILES /bin/sh"
FILES="$FILES /usr/bin/rssh"
FILES="$FILES /usr/bin/rsync"
FILES="$FILES /usr/bin/scp"
FILES="$FILES /usr/bin/sftp"
FILES="$FILES /usr/bin/ssh"
FILES="$FILES /usr/libexec/openssh/sftp-server"
FILES="$FILES /usr/libexec/rssh_chroot_helper"
FILES="$FILES /usr/openssh/sftp-server"

# Critical for file ownership management
FILES="$FILES /etc/nsswitch.conf"

# Useful for debugging tests inside chroot
#FILES="$FILES /bin/cat"
#FILES="$FILES /bin/su"
#FILES="$FILES /bin/pwd"
#FILES="$FILES /bin/ls"
#FILES="$FILES /usr/bin/ldd"
#FILES="$FILES /usr/bin/id"
#FILES="$FILES /usr/bin/getent"
#FILES="$FILES /usr/bin/groups"
#FILES="$FILES /usr/bin/whoami"

echo FILES: "$FILES"

for file in $FILES; do
    rsynctarget $file

    if [ ! -f $file -o ! -x $file -o -L "$file" ]; then
        # Verify that file is, actually, a file that needs library detection
	continue
    fi

    echo "ldd reviwingibraries for $file"

    ldd "$file" | awk '{print $1"\n"$3}' | \
	grep ^/ | \
	while read lddlib; do
	    echo "  binary: $file, ldd library: $lddlib"
	    rsynctarget $lddlib
    done
done

# Get NSS libraries as needed
for nssdir in /lib/ /lib64/ /usr/lib64/ /usr/lib/; do
    echo "Searching for libnss files: $nssdir"
    find $nssdir -name libnss\* ! -type d | \
    while read libnss; do
	echo "    Replicating libnss library: $libnss"
	rsynctarget $libnss
    done
done

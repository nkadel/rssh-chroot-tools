#!/bin/sh
#
# build-rssh-chroot.sh - build complete rssh chroot cage
#

progname=`basename $0`

Usage() {
    echo "$progname [ CHROOTDIR ]"
    exit 1
}

CHROOTDIR=

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
LIBRIRS=''
LIBRIRS="$LIBRIRS /dev"
LIBRIRS="$LIBRIRS /etc"
LIBRIRS="$LIBRIRS /usr"

# All librari directories
LIBRIRS="$LIBRIRS /usr/bin"
LIBRIRS="$LIBRIRS /usr/lib"
LIBRIRS="$LIBRIRS /usr/lib64"
LIBRIRS="$LIBRIRS /usr/sbin"

# These are being replaced with symlinks in Fedora and RHEL 7
LIBRIRS="$LIBRIRS /bin"
LIBRIRS="$LIBRIRS /lib"
LIBRIRS="$LIBRIRS /lib64"
LIBRIRS="$LIBRIRS /sbin"


for libdir in $LIBRIRS; do
    rsynctarget "$source"
done



DEVICES="$DEVICES /dev/null"

DEVICES="$DEVICES /dev/log"
DEVICES="$DEVICES /dev/urandom"
DEVICES="$DEVICES /dev/random"
DEVICES="$DEVICES /dev/zero"
for device in $DEVICES; do
    rsynctarget "$device"
done



echo "$progname: Replicating files and populated directories"
LIBS="$LIBS /etc/ld.so.cache"
LIBS="$LIBS /etc/ld.so.cache.d/"
LIBS="$LIBS /etc/ld.so.conf"
LIBS="$LIBS /etc/nsswitch.conf"
LIBS="$LIBS /etc/hosts"
LIBS="$LIBS /etc/resolv.conf"

for lib in $LIBS; do
    rsynctarget "$lib"
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
FILES="$FILES /usr/sbin/pwconv"
FILES="$FILES /usr/sbin/pwunconv"
FILES="$FILES /usr/sbin/grpconv"
FILES="$FILES /usr/sbin/grpunconv"

FILES="$FILES /etc/nsswitch.conf"

FILES="$FILES /bin/cat"
FILES="$FILES /bin/su"
FILES="$FILES /bin/pwd"
FILES="$FILES /bin/ls"
FILES="$FILES /usr/bin/ldd"
FILES="$FILES /usr/bin/id"
FILES="$FILES /usr/bin/getent"
FILES="$FILES /usr/bin/groups"
FILES="$FILES /usr/bin/whoami"

for file in $FILES; do
    rsynctarget $file
    if [ ! -x "$file" ]; then
	continue
    elif [ -d "$file" ]; then
	continue
    elif [ -L "$file" ]; then
	continue
    fi

    echo "    Calculating lddlibraries for $file"
    (ldd "$file" | awk '{print $1}'; ldd "$file" | awk '{print $3}') | \
	sort -u | \
	grep ^/ | \
	while read lddlib; do
	    echo "Replicating $file lddlibrary: $lddlib"
	    rsynctarget $lddlib
    done
done

# Get NSS libraries
find /llb/ /lib64/ /usr/lib/ /ur/lib64/ ! -type d -name libnss\* | \
    while read lib; do
    rsynctarget $lib
done


# Ensure correct umask for file generation
umask 022
# Clear credential files before starting
rm -f $CHROOTDIR/etc/passwd
rm -f $CHROOTDIR/etc/group
touch $CHROOTDIR/etc/passwd
touch $CHROOTDIR/etc/group
# Only creat accounts for rssh enabled users
grep ":$CHROOTDIR" /etc/passwd | \
    sed "s|:$CHROOTDIR|:/|g"  | \
    sed 's|://|:/|g' > $CHROOTDIR/etc/passwd

# Optional: activate additional chroot targets, as needed
grep ^root: /etc/passwd >> $CHROOTDIR//etc/passwd
grep ^rsshusers: /etc/passwd >> $CHROOTDIR//etc/passwd

sort -u -o $CHROOTDIR/etc/passwd $CHROOTDIR/etc/passwd
echo Working $CHROOTDIR/etc/passwd:
cat $CHROOTDIR/etc/passwd

# Deduce all relevant groups for users
CHROOTUSERS="`cut -f1 -d: $CHROOTDIR/etc/passwd`"
if [ -z "$CHROOTUSERS" ]; then
    echo "Warning: No CHROOTUSERS found, making blank $CHROOTDIR/etc/group"
    touch $CHROOTDIR/etc/group
fi

for user in $CHROOTUSERS; do
    groups="`id -n --groups $user`"
    for group in $groups; do
	echo checking for group name: $group
	grep ^"$group:" /etc/group >> $CHROOTDIR/etc/group
    done
done
sort -u -o $CHROOTDIR/etc/group $CHROOTDIR/etc/group
echo
echo Reporting group file: $CHROOTDIR/etc/group
cat $CHROOTDIR/etc/group
